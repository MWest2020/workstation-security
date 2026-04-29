# Changelog

## 2026-04-29

### Gefixt
- `common/rkhunter-check.sh` — guard toegevoegd: skip met exit 0 als `rkhunter` niet in PATH zit. Voorheen logde de service elke nacht stil `rkhunter: command not found` op hosts zonder rkhunter (Alma in dit geval), terwijl systemd exit 0/SUCCESS rapporteerde. Spiegelt het gedrag dat `update.sh` al had.
- `check.sh` — signature-leeftijdscheck kijkt nu naar de nieuwste van `daily.c?d` en `main.c?d` i.p.v. alleen `main.c?d`. `main.cvd` wordt zelden ge-update (versie 63 sinds weken), dus de oude check rapporteerde false-positive "19 dagen oud" terwijl `daily.cld` dezelfde dag nog door freshclam was ververst.

## 2026-04-28

### Gefixt
- `alma/install.sh` — zet `antivirus_can_scan_system` SELinux boolean aan na ClamAV-install. Zonder deze boolean blokkeert SELinux `clamscan` (`antivirus_exec_t`) op `/home`; symptoom was `clamav-scan.service` die elke nacht faalde met `status=2/INVALIDARGUMENT` en `Scanned files: 0`. Bestaande Alma-hosts: handmatig `sudo setsebool -P antivirus_can_scan_system 1` draaien en `sudo bash common/install-timers.sh` opnieuw uitvoeren om de unit te verversen naar de wrapper-versie.

## 2026-04-12

### Toegevoegd
- `ubuntu/install.sh` — installatiescript voor Ubuntu/Debian (apt)
- `common/scan.sh` — ClamAV scan wrapper met exclude-patterns en `wall`-notificatie bij vondsten
- `common/rkhunter-check.sh` — rkhunter wrapper met `wall`-notificatie bij waarschuwingen
- `common/uninstall.sh` — verwijdert systemd timers, unit files en logrotate config
- `common/logrotate.conf` — log-rotatie voor ClamAV en rkhunter logs
- `.github/workflows/shellcheck.yml` — CI met ShellCheck voor alle shell scripts

### Gewijzigd
- `common/install-timers.sh` — gebruikt nu wrapper scripts (scan.sh, rkhunter-check.sh) en installeert logrotate config
- `common/update.sh` — detecteert nu pacman vs dnf (werkt op zowel Alma als Arch)
- `README.md` — timer schema's gecorrigeerd (dagelijks, niet wekelijks) en nieuwe secties toegevoegd

### Gefixt
- README vermeldde "Zondag" voor scan/rkhunter timers, maar die zijn dagelijks
- `update.sh` gebruikte hardcoded `dnf`, werkte niet op Arch
