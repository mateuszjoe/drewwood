[CmdletBinding()]
param(
    [string]$EnvFile = ".env.deploy"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).ProviderPath
$EnvPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $ProjectRoot $EnvFile }

function Read-EnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }

        if ($line -match "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$") {
            $value = $Matches[2].Trim()
            if ($value.Length -ge 2) {
                $first = $value.Substring(0, 1)
                $last = $value.Substring($value.Length - 1, 1)
                if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }

            $values[$Matches[1]] = $value
        }
    }

    return $values
}

$envValues = Read-EnvFile -Path $EnvPath
$ftpHost = $envValues["FTP_HOST"]
$ftpPort = if ($envValues.ContainsKey("FTP_PORT")) { [int]$envValues["FTP_PORT"] } else { 21 }
$ftpUser = $envValues["FTP_USER"]
$ftpPassword = $envValues["FTP_PASSWORD"]
$remoteDir = if ($envValues.ContainsKey("FTP_REMOTE_DIR")) { $envValues["FTP_REMOTE_DIR"].Trim("/") } else { "www" }
$protocol = if ($envValues.ContainsKey("FTP_PROTOCOL")) { $envValues["FTP_PROTOCOL"].Trim().ToLowerInvariant() } else { "ftp" }
$enableSsl = $protocol -eq "ftps"

if ([string]::IsNullOrWhiteSpace($ftpHost) -or [string]::IsNullOrWhiteSpace($ftpUser) -or [string]::IsNullOrWhiteSpace($ftpPassword)) {
    throw "Missing FTP_HOST, FTP_USER or FTP_PASSWORD in $EnvPath."
}

$uri = "ftp://${ftpHost}:${ftpPort}/${remoteDir}/"
Write-Host "Testing: ${protocol}://${ftpHost}:${ftpPort}/$remoteDir"
Write-Host "User:    $ftpUser"

$request = [System.Net.FtpWebRequest]::Create($uri)
$request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
$request.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPassword)
$request.EnableSsl = $enableSsl
$request.UsePassive = $true
$request.UseBinary = $true
$request.KeepAlive = $false
$request.Timeout = 30000
$request.ReadWriteTimeout = 30000

$response = $null
$reader = $null
try {
    $response = $request.GetResponse()
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    $listing = $reader.ReadToEnd().Trim()

    Write-Host "FTP login OK."
    Write-Host "Remote listing:"
    if ($listing.Length -gt 0) {
        Write-Host $listing
    }
    else {
        Write-Host "(empty directory)"
    }
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }
    if ($null -ne $response) {
        $response.Close()
    }
}
