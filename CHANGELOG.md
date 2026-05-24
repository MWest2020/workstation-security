# Changelog

## 2026-05-24 — Freshclam-daemon redundantie weg + check.sh first-active-wins symmetrie

### Gefixt (twee bugs, ontdekt doordat `check.sh` op een sinds 2026-05-19 idle `clamav-freshclam.service` bleef vlaggen)

- **Daemon-laat-dood-achter bug** — `common/install-base.sh::freshclam_safe` stopt `clamav-freshclam.service` voordat het `freshclam` als oneshot draait, maar herstart de daemon niet. Sinds 2026-05-18 wordt deze helper ook door `av-update.timer` (04:00) gebruikt (voorheen alleen install-tijd). Effect: de eerste keer dat de timer vuurde stopte hij de daemon, die nooit meer aanging. Functioneel niet erg (signatures bleven vers via diezelfde timer-oneshot), maar wel een audit-irritant: ✗ in `check.sh`-output zonder dat er iets stuk was, plus stale runtime-state ("enabled but dead" daemon). Root cause: twee mechanismen voor één taak (long-running freshclam-daemon + oneshot-via-timer) die elkaars log-lock blokkeren. Fix: één mechanisme. `disable_freshclam_daemon` nieuwe helper in `install-base.sh`; `alma/install.sh`, `arch/install.sh`, `ubuntu/install.sh` roepen hem aan en laten `clamav-freshclam` weg uit `enable_clamav_services`. `clamav-scan.service` heeft `After=clamav-freshclam.service` niet meer (dependency op een ge-disable'd unit is misleidend; scan 02:00 vs update 04:00 conflicteren toch niet). `freshclam_safe` blijft bestaan als defensieve safety net voor gemigreerde installs en post-pakket-update scenario's waar de daemon alsnog door dnf/apt-preset wordt aangezet.

- **check.sh first-active-wins symmetrie** — comment in `common/lib.sh::WS_CLAMAV_DAEMON_CANDIDATES` zei *"eerste actieve wint in check.sh"*, maar de loop in `check.sh` iterateerde alle candidates en deed `((errors++))` op iedere inactieve. Op Alma stonden zowel `clamav-freshclam` als `clamd@scan` in `systemctl list-units`, dus alle twee werden geëvalueerd terwijl er maar één scan-daemon-actief-nodig is. Plus: `clamav-freshclam` is geen scan-daemon — het is de signature-updater die we niet meer gebruiken. Fix: `clamav-freshclam` uit `WS_CLAMAV_DAEMON_CANDIDATES` (alleen scan-daemons over: `clamd@scan`, `clamav-daemon`). `check.sh` loopt nu met early-break op de eerste actieve hit; maximaal 1 error uit deze sectie, comment en gedrag matchen.

### Migratie-stap voor bestaande installs

Eénmalig per machine (bestaande installs hebben `clamav-freshclam.service` nog als `enabled but inactive` staan; nieuwe installs via `bootstrap.sh` doen dit automatisch):

```bash
sudo systemctl daemon-reload                          # ruimt pending warning op
sudo systemctl disable --now clamav-freshclam.service # weg uit enabled-set
```

Daarna brengt `bash check.sh` een schoon overzicht zonder de spurious freshclam-fail.

## 2026-05-18 (avond) — Docs + review-fixes

### Toegevoegd
- `docs/` directory met aanvullende documentatie naast hoofd-README. Drie files: `README.md` (index, hoe te gebruiken per audience), `compliance.md` (mapping van workstation-security componenten op control-IDs in vier frameworks: ISO 27001:2022 Annex A, SOC 2 Trust Services Criteria 2017 CC6/CC7/CC8/CC9, NEN 7510-2:2017, en BIO V1.04), en `threat-model.md` (in-scope/out-of-scope met expliciete reasoning en operating assumptions). Aanleiding: audit-evidence wordt sterker wanneer een auditor naar `docs/compliance.md#A.8.7` kan navigeren in plaats van scripts te moeten lezen. Eerste pass — control-mapping is geverifieerd tegen framework-hoofdsecties maar niet woord-voor-woord tegen de letterlijke control-tekst. Voor audit-ready scope: trim de doc tot de frameworks die voor die specifieke audit in scope zijn en valideer dáár woord-voor-woord.

### Gefixt (vier bugs uit review op de WSL-commits c349766 / abb1f8d)
- `common/update.sh` riep `freshclam` direct aan i.p.v. `freshclam_safe`. `clamav-freshclam.service` houdt de log-lock vast; een tweede freshclam-aanroep faalt silently. `av-update.timer` (04:00) race't dus tegen de daemon na `enable_clamav_services`. Effect: stale signatures als audit-non-conformity. Fix: source `install-base.sh`, gebruik `freshclam_safe` die de service eerst stopt.
- `arch/install.sh` gebruikte `pacman -Sy --noconfirm clamav` zonder `-u`. Partial-upgrade is op Arch een footgun: package-database wordt ververst terwijl geïnstalleerde packages oud blijven; verse deps matchen niet meer met oude binaries. Fix: `pacman -Syu --noconfirm`.
- `bootstrap.sh:35` had `[[ ! -x "$installer" && ! -f "$installer" ]]` — tautologisch (een executable bestand is per definitie ook een bestand). De `-f`-tak verzwakte de check tot "alleen falen als beide false". Fix: vereenvoudigd tot `[[ ! -f "$installer" ]]`.
- `common/incident-token-revoke.sh::detect_heuristic` gebruikte `grep -rlE` zonder `-I`. Op een corrupt of binair bestand stopt grep met non-zero exit; alle hits in die find-walk daarna gaan verloren (de `|| true` vangt de exit, partial output is al kwijt). In een IR-context (silent-miss > over-flag) verkeerde failure-mode. Fix: `grep -rlEI`.

### Gewijzigd
- `common/install-shell-tools.sh` — sha256-verificatie toegevoegd voor `shfmt` en `gitleaks` downloads. `verify_sha256()` (pure check, geen side-effects op het bestand) + `fetch_expected_sha256()` (haalt verwachte hash uit upstream sha256sums.txt / checksums.txt). Bij mismatch: caller rmt de tmpfile en return 1. Unit-getest: positive match werkt, negative case wordt rejected zonder destructive side-effect. Ironie-fix: een tool die over supply-chain-paranoia gaat, mag zelf niet binaries downloaden zonder integriteits-check.
- `common/rkhunter-check.sh` — WSL-skip met expliciete uitleg. `rkhunter --check` geeft op WSL false-positives op /proc-checks, passwd-checks rond WSL's init-proces, en system_configs.t (verwacht init-scripts). Daily wall-notificaties met onbetrouwbare waarschuwingen leiden tot alarm-fatigue — op zichzelf een ISO 27001-bevinding. Plus: WSL's container-isolatie verandert het rootkit-bedreigingsmodel; Defender/EDR op de Windows-host is daar de juiste laag.
- `common/incident-token-revoke.sh` — clipboard-cascade uitgebreid met `clip.exe` (WSL2 native, altijd in PATH via wsl-interop). URL-opener toegevoegd: `wslview` (uit wslu package) of `cmd.exe /c start <url>` als fallback — opent de Windows-default-browser direct vanuit WSL. In een IR-context tellen seconden tussen detect en revoke; minder manual context-switching helpt.
- `README.md` — link naar `docs/` toegevoegd in intro + BIO toegevoegd aan framework-lijst. WSL Support compatibility-matrix uitgebreid met rkhunter (bewust uit op WSL) + clipboard-rij.

## 2026-05-18 (later)

### Toegevoegd
- WSL-aware runtime — alle scripts detecteren WSL en passen gedrag aan in plaats van hard te falen op ontbrekende systemd. Native alma/arch/ubuntu blijft identiek werken; WSL2-installaties van diezelfde distros draaien dezelfde installer-paden en krijgen waar nodig duidelijke skip-messages plus opt-in-instructies voor `[boot] systemd=true`. Geen aparte "wsl/" subdir — één codebase, drie distros × twee runtimes (native + WSL).
- `ws_is_wsl()` en `ws_systemd_available()` helpers in `common/lib.sh` — detectie via `/proc/sys/kernel/osrelease` (vangt zowel WSL1 als WSL2 kernel-suffix) en `ps -p 1 -o comm=` (vangt WSL2-zonder-opt-in waar `/run/systemd/system` bestaat maar PID 1 geen systemd is).
- `README.md` — nieuwe "WSL Support" sectie met compatibility-matrix (welke componenten werken native vs WSL-zonder-systemd vs WSL-met-systemd-opt-in), opt-in-instructies (`/etc/wsl.conf` + `wsl --shutdown`), en de IR-scope-limit waarschuwing.

### Gewijzigd
- `common/install-timers.sh` — WSL-guard bovenaan: als `ws_systemd_available` false is, warn + skip + clean exit 0. Op WSL gespecialiseerde uitleg met de drie-stappen opt-in. Op native Linux zonder systemd: generieke warning. Vervangt het oude scenario waar `systemctl daemon-reload` faalt met cryptische error.
- `check.sh` — systemd-afhankelijke secties (Services + Timers) gewrapped in `ws_systemd_available`-check. Op WSL zonder systemd: één geconsolideerde skip-message met opt-in-instructie, geen false-positive failures. Signature/log-checks blijven gewoon draaien (niet systemd-afhankelijk).
- `common/scan.sh` — sourcet nu `lib.sh` en voegt `--exclude-dir='^/mnt/'` toe wanneer `ws_is_wsl` true is. Voorkomt uren-durende scans van Windows-drives via DrvFs. Native Linux: `/mnt` wordt NIET uitgesloten (vaak legitiem mountpoint voor tijdelijke media).
- `common/incident-token-revoke.sh` — print bij start van een Linux-run een scope-limit waarschuwing als WSL gedetecteerd is. Persistence-mechanismen op de Windows-host (Task Scheduler, HKCU Run-keys, startup folder) zijn buiten WSL's bereik en dus buiten dit script — operator krijgt expliciete PowerShell + reg-commands om Windows-kant óók te auditen. Inline WSL-detectie (geen lib.sh dependency) want het IR-script blijft self-contained voor emergency-runs.

### Maintainability-noten
- `ws_systemd_available` is een tweevoudige check (`/run/systemd/system`-dir + `ps -p 1 -o comm=`). De directory-only check zou false-positive geven op WSL2 zonder `[boot] systemd=true` als een ander proces ooit /run/systemd/system heeft aangemaakt. De PID-1-check is de definitieve.
- WSL-detectie via `/proc/sys/kernel/osrelease` is robust voor beide WSL-generaties. Microsoft heeft de string ge-rebrand van "Microsoft" (WSL1) naar "microsoft-standard-WSL2" (WSL2) — case-insensitive grep op `microsoft|wsl` vangt beide.
- Toevoegen van een nieuwe WSL-quirk: ws_is_wsl is de centrale gate. Voor distro-specifieke quirks blijven `alma/install.sh` / `arch/install.sh` / `ubuntu/install.sh` de plek; voor runtime-specifieke quirks komt logic in de gedeelde scripts onder een `ws_is_wsl`-check.

## 2026-05-18

### Toegevoegd
- `common/install-shell-tools.sh` — user-level installer voor de shell-tooling-stack (shfmt v3.10.0, gitleaks v8.30.6, pre-commit, jscpd). Aanvullend op shellcheck (distro pkg). Idempotent: re-run upserts, pinned versies worden overgeslagen als al geïnstalleerd. Routes via `~/.local/bin/` en `~/.npm-global/bin/` (laatste via `npm config set prefix --location=user`, niet sudo). Detecteert OS+arch automatisch voor binary downloads. `--check` voor read-only state, `--tool <name>` voor selectieve install. Aanleiding: review van Hydra PR #269 surfaced dat `set -euo pipefail`, env-loading-duplicatie en jq-filter-copy-paste alleen automatisch gevangen worden met een gestapelde tool-set (zie [ConductionNL/hydra#280](https://github.com/ConductionNL/hydra/issues/280)). Tools werken als gates (`--check`/read-only) — geen auto-fix, consistent met `iso-audit`'s pre-commit-philosophie.
- `common/check-shell-headers.sh` — header-convention validator voor `.sh` files. Controleert: shebang (`#!/usr/bin/env bash` of `#!/bin/bash`), `SPDX-License-Identifier` in eerste 5 regels, `# role: <entrypoint|library|container-entrypoint|installer|tool>` marker, `set -euo pipefail` voor role=entrypoint/installer, en een `# Usage:` block voor role=entrypoint/installer/tool. Standalone uitvoerbaar (`<file>` / `--all <dir>` / `--pre-commit` voor hook-mode-stdin). Exit-code = aantal violations. Read-only, geen side effects. ISO 27001-context: `grep -rn '^# role:' scripts/` toont in één oog-oogslag alle process-boundaries van een repo — auditeerbaar zonder de hele file te moeten lezen.
- `common/templates/bash-script-template.sh` — boilerplate die de check-shell-headers conventie codificeert. Begin-punt voor nieuwe scripts: SPDX + role + uitgebreid header-blok (what/why, writes, idempotency, requires, style-afwijkingen, usage met 3+ voorbeelden, crontab/Docker CMD waar applicable), `set -euo pipefail`, `main()` pattern, helpers-skelet. Eén kopieer-en-aanpassen-actie voor nieuwe scripts.
- `common/templates/pre-commit-config-shell.yaml.example` — drop-in `.pre-commit-config.yaml` voor shell-heavy repos. Wires: shellcheck (severity=warning), shfmt --check (i=2, ci, bn), gitleaks, jscpd (min-tokens=50, threshold=0), en `check-shell-headers.sh`. Allemaal in --check / gate modus — geen `--write` / `--fix` / auto-rewrite hooks. Hetzelfde "poortwachter, niet auto-correct"-principe als `iso-audit/.pre-commit-config.yaml`.

### Gewijzigd
- `common/install-pm-cooldown.sh` — SPDX-License-Identifier en `# role: installer` marker toegevoegd in de header, conform de nieuwe `check-shell-headers.sh` conventie. Pre-existing functioneel correct, alleen header-metadata aangevuld zodat de installer zelf conformeert aan de regels die hij meebrengt.
- `common/templates/README.md` — uitgebreid met de nieuwe shell-script conventie + pre-commit-gates-sectie. Tabel met "what to drop in" bevat nu ook `pre-commit-config-shell.yaml.example` en `bash-script-template.sh`. Verwijst naar `install-shell-tools.sh` als prerequisite.

### Maintainability-noten
- De `# role:` marker is de centrale haak voor toekomstige policy-checks. Vandaag controleert `check-shell-headers.sh` op aanwezigheid + waarde; later kan dezelfde marker gebruikt worden voor: routing in pre-commit (entrypoint vereist load_env-call, library niet), dependency-graph-rendering (welke entrypoints sourcen welke libraries), of audit-reports voor ISO 27001.
- Tool-versies (shfmt, gitleaks) zijn pinned in `install-shell-tools.sh` met `readonly` constants. Bump deliberately, document waarom in een CHANGELOG-entry. pre-commit en jscpd zijn niet gepinned op de binary (krijgen per-project pinning via `.pre-commit-config.yaml` / `package.json`).

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

### Docs
- `README.md` intro herschreven om de werkelijke scope te dekken. Oude intro ("Install scripts voor ClamAV en rkhunter ... antiviruseis") onderschatte de scope met factor 3+ nadat supply-chain cooldown, incident-token-revoke, `check.sh` en `bootstrap.sh` waren toegevoegd. Nieuwe intro: drie verdedigingslagen (AV+rootkit / supply-chain / IR), doelgroep (dev workstations, niet servers), target-distros, en de compliance-frame (ISO 27001 / SOC 2 / NEN 7510). Geen marketing, scope-helder zodat een nieuwe lezer in 30 seconden weet wat de repo doet.

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
