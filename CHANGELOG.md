# Changelog

## 2026-05-13

### Toegevoegd
- `common/install-pm-cooldown.sh` — user-level installer (geen sudo) die 7-daagse pakket-cooldown configureert voor npm, pnpm en bun. Schrijft `min-release-age` (npm 11.10+) + `minimum-release-age` (pnpm 10.16+) in `~/.npmrc`, en `[install] minimumReleaseAge` (bun 1.3+) in `~/.bunfig.toml`. Idempotent, behoudt bestaande inhoud (auth tokens, registries) en file-mode (default 0600 voor nieuwe files). Context: npm yankt malicious supply-chain versies meestal binnen 24-48u; een 7-daags venster vangt ze vóór ze in een lockfile landen. Aanleiding: npm supply-chain incident van 2026-05-11. `--days N` voor andere window, `--check` voor read-only inspectie.
- `common/lib.sh` — gedeelde library: arrays met timer-/service-namen (single source of truth) + status-icoon helpers (`ws_ok` / `ws_fail` / `ws_warn` / `ws_skip`). Niet zelfstandig uitvoerbaar; source-guard tegen dubbele inclusie.
- `common/install-base.sh` — gedeelde install-helpers voor de OS-scripts: `require_root`, `freshclam_safe`, `rkhunter_init`, `enable_clamav_services`, `install_timers`, `print_summary`. Source-only library.
- `bootstrap.sh` — top-level OS-dispatcher. Leest `/etc/os-release` en draait de juiste `alma/arch/ubuntu install.sh` automatisch. Valt terug op `ID_LIKE` voor onbekende derivatives (Rocky → alma, Manjaro → arch, Mint → ubuntu, etc.).
- `common/templates/` — project-lokale `.npmrc` + `bunfig.toml` voorbeelden voor de cooldown. Dekt de gap die `install-pm-cooldown.sh` openlaat: CI/CD-runners lezen `~/.npmrc` niet, dus per-project files in de repo zorgen dat de cooldown ook in pipelines telt. Inclusief `templates/README.md` met gebruiks/CI-env-var/override-instructies. Vanuit hoofd-README gelinkt onder de "Package-manager cooldown" sectie.

### Gewijzigd
- `common/incident-token-revoke.sh` — style-afwijkingen t.o.v. Google Shell Style baseline expliciet gedocumenteerd in de header (per `~/.claude/CLAUDE.md` regel "no exceptions without a written reason in the script"): shebang via `env bash` (i.v.m. macOS bash 3.2), en `set -e` bewust UIT (zou de IR-flow vroegtijdig laten exiten bij verwachte non-zero exits van pkill/systemctl/grep -q op een schone machine).
- `common/install-pm-cooldown.sh` — shebang van `/bin/bash` naar `/usr/bin/env bash` gezet voor consistentie met de rest van het repo. Reden onder de shebang gedocumenteerd.
- `common/install-timers.sh` — enable-loop leest nu `WS_TIMERS` uit `lib.sh` i.p.v. drie hardcoded `systemctl enable --now`-regels. Drift-smoke-test aan het eind: faalt als er een timer in de array zit zonder bijhorende heredoc.
- `common/uninstall.sh` — disable + verwijder-loops itereren over `WS_TIMERS` en `WS_SERVICES_GENERATED`. Toevoegen van een nieuwe timer is voortaan één edit in `lib.sh` (i.p.v. drie: hier, in `install-timers.sh`, en in `check.sh`).
- `check.sh` — gebruikt nu `WS_TIMERS` + `WS_CLAMAV_DAEMON_CANDIDATES` uit `lib.sh` (was: hardcoded). Status-iconen via gedeelde `ws_*` helpers. **Gedragschange**: exit-code is voortaan gelijk aan het aantal gevonden problemen (capped op 2). Hiervoor was `check.sh` altijd `exit 0`, ook bij errors — wat 'm useless maakte voor cron/CI/monitoring. Wie scripts heeft die `check.sh` aanroepen en op exit 0 vertrouwen: aanpassen.
- `alma/install.sh` / `arch/install.sh` / `ubuntu/install.sh` — gemeenschappelijke skeleton (root-check, freshclam-safe, rkhunter-init, services-enable, install-timers-call, resultaatsamenvatting) verplaatst naar `common/install-base.sh`. Per-OS scripts behouden alleen pkg-manager-commando's, daemon-namen, en OS-specifieke quirks: SELinux-boolean op Alma, `/var/lib/clamav`-chown op Arch, en de `set +e`/`set -e`-wrapper rond `rkhunter_init` op Arch (rkhunter daar geeft non-zero op deprecated egrep-call). Status-iconen via gedeelde helpers; `[OK]/[FAIL]/[SKIP]` is `✓/✗/-` geworden voor consistentie met `check.sh`.
- `common/scan.sh` + `common/rkhunter-check.sh` — style-afwijking t.o.v. Google Shell Style baseline expliciet gedocumenteerd in de header. `set -e` is UIT (was al zo, nu met reden): beide scripts moeten de non-zero exit van hun gewrapped tool juist DETECTEREN (clamscan exit 1 = infectie, rkhunter exit ≠ 0 = warning) en daarna een `wall`-notificatie sturen — niet aborten.

### Maintainability-noten
- Single source of truth voor timer-/service-namen zit nu in `lib.sh`. Een nieuwe timer toevoegen vereist twee edits: de array in `lib.sh` en de bijhorende heredoc in `install-timers.sh`. De drift-smoke-test in `install-timers.sh` vangt vergeten heredocs.
- De OS-installers zijn nu ~30 regels elk (was ~50-60), met de quirks expliciet gemarkeerd. Toevoegen van een nieuwe distro (bv. SUSE) = nieuw `<os>/install.sh` met dezelfde 30-regels-structuur.

### Gefixt
- `check.sh` — Services-blok bleef leeg op machines waar de ClamAV-daemon wél draaide. Oorzaak: `set -o pipefail` + `grep -q` early-exit gaf systemctl een SIGPIPE; pipefail propageerde dat als pipeline-exit 141, en `if !` interpreteerde dat als "niet aanwezig" → `continue`. Fix: `systemctl list-units`-output éénmaal capture'n, daarna per candidate `grep -qE … <<<"$units_output"` (here-string, geen pipe, geen SIGPIPE). Eén `systemctl`-call i.p.v. drie. Pre-existing bug; surfaced door de refactor-smoke-test.
- `common/incident-token-revoke.sh` — zelfde SIGPIPE-patroon zat in `detect_linux` (`systemctl --user list-units … | awk … | grep -qi`) en `detect_macos` (`launchctl list | awk … | grep -q`). Op een gecompromitteerde machine met de actieve unit zou de pipeline op precies dezelfde manier exit 141 geven en de IOC-flag NIET zetten → silent miss van het exacte ding waar deze script voor bestaat. Beide refactored naar capture-eerst-dan-here-string. Repo-wide audit gedaan op overige `grep -q` in pipes; geen verdere instances.

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
