# Deploy strony Drewwood

Ten projekt ma gotowy deploy przez FTP/FTPS dla publicznych plikow strony `https://www.drewwood.com.pl`.

Domyslnie wysylane sa tylko elementy z `deploy.include`: strona glowna, blog, style, skrypty, sitemap, robots, zdjecia, wideo i `.htaccess`. Skrypt celowo pomija m.in. `administrator/` oraz `configuration.php`, zeby regularny deploy nie nadpisywal konfiguracji hostingu ani panelu Joomla.

## Deploy lokalny

1. Uzupelnij dane FTP w lokalnym pliku `.env.deploy`:

```env
FTP_HOST=ftp.cluster020.hosting.ovh.net
FTP_PORT=21
FTP_USER=twoj_login
FTP_PASSWORD=twoje_haslo
FTP_REMOTE_DIR=/www
FTP_PROTOCOL=ftp
FTP_PASSIVE=true
SITE_URL=https://www.drewwood.com.pl
```

2. Sprawdz, co zostanie wyslane:

```powershell
.\deploy.cmd -DryRun
```

3. Sprawdz samo polaczenie FTP bez wysylania plikow:

```powershell
.\test-ftp.cmd
```

4. Wyslij zmiany:

```powershell
.\deploy.cmd
```

Skrypt porownuje rozmiar pliku na serwerze i pomija pliki, ktore wygladaja na juz wyslane. Gdy chcesz wymusic pelny upload wybranych plikow:

```powershell
.\deploy.cmd -Force
```

## Automatyczny deploy z GitHuba

Workflow `.github/workflows/ftp-deploy.yml` uruchamia deploy po kazdym pushu do `main` oraz recznie z zakladki Actions.

W repozytorium GitHub dodaj sekrety:

- `FTP_HOST`
- `FTP_PORT` opcjonalnie, domyslnie `21`
- `FTP_USER`
- `FTP_PASSWORD`
- `FTP_REMOTE_DIR` opcjonalnie, dla OVH najczesciej `/www`
- `FTP_PROTOCOL` opcjonalnie, dla tego konta ustawione na `ftp`
- `FTP_PASSIVE` opcjonalnie, domyslnie `true`

Po ustawieniu sekretow wystarczy `git push` na branch `main`.

Jesli panel hostingu pokazuje inny serwer FTP niz `ftp.cluster020.hosting.ovh.net`, wpisz go jako `FTP_HOST`.

## Zmiana listy plikow

Jesli dodasz nowy publiczny katalog albo plik, dopisz go do `deploy.include`. Nie dopisuj tam `.env.deploy`, `configuration.php` ani katalogu `administrator/`, chyba ze robisz swiadomy deploy administracyjnej czesci hostingu.
