# Changelog

## 2026-05-13

### Toegevoegd
- `common/install-pm-cooldown.sh` — user-level installer (geen sudo) die 7-daagse pakket-cooldown configureert voor npm, pnpm en bun. Schrijft `min-release-age` (npm 11.10+) + `minimum-release-age` (pnpm 10.16+) in `~/.npmrc`, en `[install] minimumReleaseAge` (bun 1.3+) in `~/.bunfig.toml`. Idempotent, behoudt bestaande inhoud (auth tokens, registries) en file-mode (default 0600 voor nieuwe files). Context: npm yankt malicious supply-chain versies meestal binnen 24-48u; een 7-daags venster vangt ze vóór ze in een lockfile landen. Aanleiding: npm supply-chain incident van 2026-05-11. `--days N` voor andere window, `--check` voor read-only inspectie.

### Gewijzigd
- `common/incident-token-revoke.sh` — style-afwijkingen t.o.v. Google Shell Style baseline expliciet gedocumenteerd in de header (per `~/.claude/CLAUDE.md` regel "no exceptions without a written reason in the script"): shebang via `env bash` (i.v.m. macOS bash 3.2), en `set -e` bewust UIT (zou de IR-flow vroegtijdig laten exiten bij verwachte non-zero exits van pkill/systemctl/grep -q op een schone machine).
- `common/install-pm-cooldown.sh` — shebang van `/bin/bash` naar `/usr/bin/env bash` gezet voor consistentie met de rest van het repo (alle bestaande scripts gebruiken al `env bash`). Reden onder de shebang gedocumenteerd.

## 2026-05-12

### Toegevoegd
- `common/incident-token-revoke.sh` — IR-script voor CanisterSprawl-klasse GitHub-token dead-man's switch (carlini-analyse 2026-05-12: `gh-token-monitor` polt `api.github.com/user` elke 60s en draait `rm -rf ~/` bij HTTP 40x). Detecteert hardcoded IOC's + heuristische grep over `~/.local/bin`, `~/.config/systemd/user`, `~/.config/autostart`, `~/.bashrc.d`. Vangt `gh auth token` vooraf (sha256 + last4) voor verify. Kill't processen met **SIGKILL eerst** (voor `systemctl stop` zodat een eventuele TERM-trap niet alsnog rm -rf triggert), ontwapent persistence, draait `gh auth logout`, scant `~/.config/gh/hosts.yml` + shell rc + `.netrc` voor token-resten. Print revoke-URL (er bestaat geen user-self-revoke REST endpoint voor PATs). Verifieert HTTP 401 met de gevangen token. Linux + macOS. Geen root nodig.
- `common/incident-token-revoke.env.example` — optionele Gmail SMTPS mail-skeleton. Zonder dit bestand worden er géén mails verstuurd; alles blijft lokaal.

### Ontwerp-noten
- Footprint-bewust: `/tmp/incident-<ts>/` wordt **lazy** aangemaakt (alleen bij findings), evidence-files gecapped op 1 MiB tegen symlink-naar-/dev/urandom-tricks, schone runs laten niks achter op disk. Geen separaat Markdown-dossier — de log file zelf IS het verslag.
- Evidence buiten `$HOME` (`/tmp` i.p.v. `~/.local/share`) zodat de `rm -rf ~/` window het dossier niet meeneemt.
- Heuristische treffers worden alleen gearchiveerd, NIET auto-verwijderd (false-positive op een legit script zou data weggooien — operator beslist).
- Manual revoke-prompt is bewust niet door `--yes-neutralize` te skippen; verify zonder daadwerkelijke revoke is misleidend.

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
