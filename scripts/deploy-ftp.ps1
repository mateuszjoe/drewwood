[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipVerify,
    [string]$EnvFile = ".env.deploy",
    [string]$IncludeFile = "deploy.include",
    [string]$RemoteDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).ProviderPath
$CreatedDirectories = New-Object "System.Collections.Generic.HashSet[string]"

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $ProjectRoot $Path)
}

function Read-EnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }

        if ($line -notmatch "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$") {
            Write-Warning "Skipping invalid env line: $rawLine"
            continue
        }

        $name = $Matches[1]
        $value = $Matches[2].Trim()
        if ($value.Length -ge 2) {
            $first = $value.Substring(0, 1)
            $last = $value.Substring($value.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $values[$name] = $value
    }

    return $values
}

function Get-DeployValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ""
    )

    if ($script:DeployEnv.ContainsKey($Name)) {
        $fromFile = [string]$script:DeployEnv[$Name]
        if ($fromFile.Length -gt 0) {
            return $fromFile
        }
    }

    $fromProcess = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($fromProcess)) {
        return $fromProcess
    }

    return $Default
}

function Convert-ToDeployBool {
    param(
        [string]$Value,
        [bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch -Regex ($Value.Trim().ToLowerInvariant()) {
        "^(1|true|yes|y|tak)$" { return $true }
        "^(0|false|no|n|nie)$" { return $false }
        default { return $Default }
    }
}

function Normalize-RemoteRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Trim() -eq "/") {
        return ""
    }

    $normalized = $Path.Replace("\", "/").Trim()
    if (-not $normalized.StartsWith("/")) {
        $normalized = "/" + $normalized
    }

    return $normalized.TrimEnd("/")
}

function Get-RelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $root = $ProjectRoot.TrimEnd("\", "/")

    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside project root: $fullPath"
    }

    return $fullPath.Substring($root.Length).TrimStart("\", "/")
}

function Should-SkipFile {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $relative = (Get-RelativePath -Path $File.FullName).Replace("\", "/")
    $segments = @($relative.Split("/"))

    $blockedDirectories = @(".git", ".github", "administrator", "node_modules", "vendor", "scripts")
    foreach ($segment in $segments) {
        if ($blockedDirectories -contains $segment) {
            return $true
        }
    }

    $blockedFiles = @(
        ".env",
        ".env.deploy",
        ".env.deploy.example",
        "configuration.php",
        "DEPLOY.md",
        "deploy.include"
    )

    if ($blockedFiles -contains $File.Name) {
        return $true
    }

    if ($File.Name -in @(".DS_Store", "Thumbs.db", "desktop.ini")) {
        return $true
    }

    return $false
}

function Add-DeployFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][hashtable]$Files
    )

    if (Should-SkipFile -File $File) {
        return
    }

    $relative = (Get-RelativePath -Path $File.FullName).Replace("\", "/")
    $Files[$relative] = [pscustomobject]@{
        RelativePath = $relative
        FullName     = $File.FullName
        Length       = $File.Length
    }
}

function Get-IncludedFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing include file: $Path"
    }

    $files = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $entry = $rawLine.Trim()
        if ($entry.Length -eq 0 -or $entry.StartsWith("#")) {
            continue
        }

        $localPath = Resolve-ProjectPath -Path $entry
        if (-not (Test-Path -LiteralPath $localPath)) {
            Write-Warning "Included path does not exist: $entry"
            continue
        }

        $item = Get-Item -LiteralPath $localPath -Force
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force | ForEach-Object {
                Add-DeployFile -File $_ -Files $files
            }
        }
        else {
            Add-DeployFile -File $item -Files $files
        }
    }

    return @($files.Values | Sort-Object RelativePath)
}

function Join-FtpUri {
    param([string]$RelativePath = "")

    $authority = $script:FtpHost
    if ($script:FtpPort -gt 0 -and $authority -notmatch ":\d+$") {
        $authority = "${authority}:$($script:FtpPort)"
    }

    $segments = @()
    if (-not [string]::IsNullOrWhiteSpace($script:RemoteRootNormalized)) {
        $segments += @($script:RemoteRootNormalized.Trim("/") -split "/" | Where-Object { $_.Length -gt 0 })
    }

    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        $segments += @($RelativePath.Replace("\", "/").Trim("/") -split "/" | Where-Object { $_.Length -gt 0 })
    }

    if ($segments.Count -eq 0) {
        return "ftp://$authority/"
    }

    $encodedSegments = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
    return "ftp://$authority/$($encodedSegments -join "/")"
}

function New-FtpRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Method
    )

    $request = [System.Net.FtpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Credentials = New-Object System.Net.NetworkCredential($script:FtpUser, $script:FtpPassword)
    $request.EnableSsl = $script:FtpEnableSsl
    $request.UsePassive = $script:FtpPassive
    $request.UseBinary = $true
    $request.KeepAlive = $false
    $request.Timeout = $script:FtpTimeoutMs
    $request.ReadWriteTimeout = $script:FtpTimeoutMs
    return $request
}

function Ensure-RemoteDirectory {
    param([string]$RelativeDirectory)

    if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        return
    }

    $current = ""
    foreach ($part in @($RelativeDirectory.Replace("\", "/").Trim("/") -split "/" | Where-Object { $_.Length -gt 0 })) {
        if ($current.Length -eq 0) {
            $current = $part
        }
        else {
            $current = "$current/$part"
        }

        if ($script:CreatedDirectories.Contains($current)) {
            continue
        }

        if ($DryRun) {
            Write-Host "DIR  $current"
            [void]$script:CreatedDirectories.Add($current)
            continue
        }

        $uri = Join-FtpUri -RelativePath $current
        $response = $null
        try {
            $request = New-FtpRequest -Uri $uri -Method ([System.Net.WebRequestMethods+Ftp]::MakeDirectory)
            $response = $request.GetResponse()
        }
        catch [System.Net.WebException] {
            $ftpResponse = $_.Exception.Response
            if ($null -eq $ftpResponse -or $ftpResponse.StatusCode -ne [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable) {
                throw
            }
        }
        finally {
            if ($null -ne $response) {
                $response.Close()
            }
        }

        [void]$script:CreatedDirectories.Add($current)
    }
}

function Get-RemoteFileSize {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $response = $null
    try {
        $uri = Join-FtpUri -RelativePath $RelativePath
        $request = New-FtpRequest -Uri $uri -Method ([System.Net.WebRequestMethods+Ftp]::GetFileSize)
        $response = $request.GetResponse()
        return [int64]$response.ContentLength
    }
    catch [System.Net.WebException] {
        return $null
    }
    finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }
}

function Upload-File {
    param([Parameter(Mandatory = $true)]$File)

    $remoteDirectory = Split-Path -Path $File.RelativePath -Parent
    if ($remoteDirectory -ne ".") {
        Ensure-RemoteDirectory -RelativeDirectory $remoteDirectory
    }

    if (-not $Force -and -not $DryRun) {
        $remoteSize = Get-RemoteFileSize -RelativePath $File.RelativePath
        if ($null -ne $remoteSize -and $remoteSize -eq $File.Length) {
            Write-Host "SKIP $($File.RelativePath)"
            return "skipped"
        }
    }

    if ($DryRun) {
        Write-Host "PUT  $($File.RelativePath)"
        return "planned"
    }

    $uri = Join-FtpUri -RelativePath $File.RelativePath
    $request = New-FtpRequest -Uri $uri -Method ([System.Net.WebRequestMethods+Ftp]::UploadFile)
    $request.ContentLength = $File.Length

    $sourceStream = $null
    $targetStream = $null
    $response = $null
    try {
        $sourceStream = [System.IO.File]::OpenRead($File.FullName)
        $targetStream = $request.GetRequestStream()
        $sourceStream.CopyTo($targetStream)
        $targetStream.Close()
        $sourceStream.Close()

        $response = $request.GetResponse()
        Write-Host "PUT  $($File.RelativePath)"
        return "uploaded"
    }
    finally {
        if ($null -ne $targetStream) {
            $targetStream.Dispose()
        }
        if ($null -ne $sourceStream) {
            $sourceStream.Dispose()
        }
        if ($null -ne $response) {
            $response.Close()
        }
    }
}

function Invoke-SiteCheck {
    if ($SkipVerify -or [string]::IsNullOrWhiteSpace($script:SiteUrl) -or $DryRun) {
        return
    }

    try {
        $response = Invoke-WebRequest -Uri $script:SiteUrl -UseBasicParsing -TimeoutSec 30
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            Write-Host "OK   $($script:SiteUrl) returned HTTP $($response.StatusCode)"
        }
        else {
            Write-Warning "$($script:SiteUrl) returned HTTP $($response.StatusCode)"
        }
    }
    catch {
        Write-Warning "Deploy finished, but verification failed: $($_.Exception.Message)"
    }
}

$EnvPath = Resolve-ProjectPath -Path $EnvFile
$IncludePath = Resolve-ProjectPath -Path $IncludeFile
$DeployEnv = Read-EnvFile -Path $EnvPath

$FtpHost = Get-DeployValue -Name "FTP_HOST" -Default "ftp.cluster020.hosting.ovh.net"
$FtpPort = [int](Get-DeployValue -Name "FTP_PORT" -Default "21")
$FtpUser = Get-DeployValue -Name "FTP_USER"
$FtpPassword = Get-DeployValue -Name "FTP_PASSWORD"
$Protocol = (Get-DeployValue -Name "FTP_PROTOCOL" -Default "ftps").Trim().ToLowerInvariant()
$FtpPassive = Convert-ToDeployBool -Value (Get-DeployValue -Name "FTP_PASSIVE" -Default "true") -Default $true
$FtpTimeoutMs = [int](Get-DeployValue -Name "FTP_TIMEOUT_MS" -Default "120000")
$SiteUrl = Get-DeployValue -Name "SITE_URL" -Default "https://www.drewwood.com.pl"

if ([string]::IsNullOrWhiteSpace($RemoteDir)) {
    $RemoteDir = Get-DeployValue -Name "FTP_REMOTE_DIR" -Default "/www"
}

if ($Protocol -notin @("ftp", "ftps")) {
    throw "FTP_PROTOCOL must be ftp or ftps."
}

$FtpEnableSsl = $Protocol -eq "ftps"
$RemoteRootNormalized = Normalize-RemoteRoot -Path $RemoteDir

if (-not $DryRun) {
    if ([string]::IsNullOrWhiteSpace($FtpHost) -or [string]::IsNullOrWhiteSpace($FtpUser) -or [string]::IsNullOrWhiteSpace($FtpPassword)) {
        throw "Missing FTP credentials. Create .env.deploy from .env.deploy.example or set FTP_HOST, FTP_USER and FTP_PASSWORD."
    }
}

$files = Get-IncludedFiles -Path $IncludePath
if ($files.Count -eq 0) {
    throw "No files selected for deploy. Check $IncludePath."
}

Write-Host "Project: $ProjectRoot"
Write-Host "Target:  ${Protocol}://$FtpHost`:$FtpPort$RemoteRootNormalized"
Write-Host "Files:   $($files.Count)"
if ($DryRun) {
    Write-Host "Mode:    dry run"
}
elseif ($Force) {
    Write-Host "Mode:    upload all selected files"
}
else {
    Write-Host "Mode:    skip files with matching remote size"
}

$uploaded = 0
$skipped = 0
$planned = 0

foreach ($file in $files) {
    $result = Upload-File -File $file
    switch ($result) {
        "uploaded" { $uploaded++ }
        "skipped" { $skipped++ }
        "planned" { $planned++ }
    }
}

Invoke-SiteCheck

Write-Host "Done. Uploaded: $uploaded, skipped: $skipped, planned: $planned."
