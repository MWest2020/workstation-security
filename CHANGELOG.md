# Changelog

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
