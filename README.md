# workstation-security

Lichtgewicht baseline voor het hardenen van developer workstations. Bedoeld
om de minimale set verdedigingen op orde te hebben die je voor een ISO 27001
/ SOC 2 / NEN 7510 audit moet kunnen aantonen, zonder een full-blown EDR
uit te rollen.

## Drie verdedigingslagen

1. **Antivirus + rootkit** — ClamAV (dagelijkse scan van `/home`) en rkhunter
   (rootkit check), via systemd timers. Niet omdat developer workstations
   hét doelwit van klassieke virussen zijn, maar omdat de meeste
   compliance-frameworks *iets* aan AV willen zien.
2. **Supply-chain cooldown** — 7-daagse quarantine op nieuwe npm / pnpm / bun
   pakketversies. npm yankt malicious supply-chain versies meestal binnen
   24-48u; de cooldown houdt ze buiten je lockfile vóór ze worden opgemerkt.
   Aanleiding o.a. het npm supply-chain incident van 2026-05-11. User-level
   config (`~/.npmrc`, `~/.bunfig.toml`) plus per-project / CI-templates voor
   waar `~`-config niet leest.
3. **Incident response — GitHub token compromise** — losse IR-tool voor het
   CanisterSprawl-scenario: een gestolen GitHub-PAT met dead-man's switch die
   `rm -rf ~/` triggert wanneer je 'm probeert te revoken. Detecteert,
   ontwapent veilig (SIGKILL-first, evidence buiten `$HOME`), en wacht op
   handmatige revoke met verify.

Plus: een `check.sh` health-script met betekenisvolle exit-code (cron/CI),
en een `bootstrap.sh` die `/etc/os-release` leest en automatisch de juiste
OS-installer draait.

## Doelgroep en scope

- Developer workstations, **niet** servers — de aanname is dat de user
  grotendeels root is op z'n eigen machine en de defaults wil kunnen
  uitleggen aan een auditor.
- Target distros: Alma / Rocky / RHEL / Fedora / CentOS (dnf), Arch /
  Manjaro / EndeavourOS (pacman), Ubuntu / Debian / Mint / Pop / Raspbian
  (apt). macOS wordt deels ondersteund — het IR-script werkt cross-platform.
- WSL2 (Windows Subsystem for Linux) is detecteerbaar en wordt netjes
  afgehandeld — scripts skippen systemd-features waar nodig in plaats van
  hard te falen. Zie [WSL Support](#wsl-support) onderaan.

## Gebruik

Clone en installeer in één keer — daarna nooit meer naar omkijken.

### Aanbevolen: auto-detect OS

```bash
git clone https://github.com/conduction-it/workstation-security.git
cd workstation-security
sudo bash bootstrap.sh
```

`bootstrap.sh` leest `/etc/os-release` en dispatched naar de juiste installer
(alma/arch/ubuntu). Bij onbekend OS valt het terug op `ID_LIKE` en print
anders een heldere foutmelding.

### Of: directe per-OS installer

```bash
# Alma / Rocky / CentOS / RHEL / Fedora
sudo bash alma/install.sh

# Arch / Manjaro / EndeavourOS
sudo bash arch/install.sh

# Ubuntu / Debian / Mint / Pop / Raspbian
sudo bash ubuntu/install.sh
```

Na installatie draait alles automatisch via systemd timers. Geen verdere actie nodig.

## Wat wordt er geïnstalleerd?

| Package     | Functie                          |
|-------------|----------------------------------|
| `clamav`    | Antivirus scanner                |
| `clamd`     | Daemon voor realtime scanning    |
| `rkhunter`  | Rootkit detectie                 |

## Na installatie

Alles loopt automatisch via systemd timers:

| Timer                    | Wanneer         | Wat                             |
|--------------------------|-----------------|----------------------------------|
| `av-update.timer`        | Dagelijks 04:00 | Signatures + rkhunter database  |
| `clamav-scan.timer`      | Dagelijks 02:00 | Volledige scan van `/home`      |
| `rkhunter-check.timer`   | Dagelijks 03:00 | Rootkit check                   |

Bij vondsten ontvangen ingelogde gebruikers een `wall`-melding.

Logs worden automatisch geroteerd via logrotate (wekelijks, 4 weken bewaard).

## Status check

```bash
sudo bash check.sh
```

Toont services / timers / signatures / laatste scans. Exit-code is gelijk
aan het aantal gevonden problemen (capped op 2), zodat het in cron of CI
gebruikt kan worden als gezondheids-probe.

## Handmatige scan

```bash
# Volledige scan
sudo clamscan -r /home --infected --log=/var/log/clamav/manual-scan.log

# rkhunter check
sudo rkhunter --check --skip-keypress
```

## Incident response — GitHub-token dead-man's switch

Voor het CanisterSprawl-scenario (gestolen GitHub-PAT met dead-man's switch
die `rm -rf ~/` triggert bij token-revoke):

```bash
bash common/incident-token-revoke.sh --dry-run   # alleen detectie
bash common/incident-token-revoke.sh             # volledige flow
```

Werkt user-level (geen root nodig). Vangt eerst de huidige `gh`-token op
(hash + last-4) voor latere verify, detecteert IOC's + heuristisch, kill't
polling-processen met **SIGKILL voordat** systemd er een SIGTERM op stuurt
(een TERM-trap in de payload kan namelijk alsnog `rm -rf ~/` triggeren),
archiveert artefacten naar `/tmp/incident-<ts>/` (overleeft `rm -rf ~/`),
maakt de token op deze machine onbruikbaar, en wacht op handmatige revoke
op github.com/settings/tokens (er is geen user-self-revoke REST endpoint).

Schone runs laten niks achter op disk; alleen bij findings wordt
`/tmp/incident-<ts>/` aangemaakt.

### Optionele mail-rapportage

Standaard blijft alles lokaal. Voor een SMTPS-mail (bv. Gmail) na afloop:

```bash
mkdir -p ~/.config/workstation-security
cp common/incident-token-revoke.env.example ~/.config/workstation-security/mail.env
chmod 600 ~/.config/workstation-security/mail.env
$EDITOR ~/.config/workstation-security/mail.env
```

Het script weigert te mailen als die file niet op mode 600/400 staat
(bevat een App Password).

## Package-manager cooldown (npm / pnpm / bun)

Een 7-daagse quarantine op verse pakketversies verdedigt tegen
supply-chain attacks (npm yankt malicious versies doorgaans binnen 24-48u —
een 7-daagse cooldown houdt ze buiten je lockfile vóór ze opgemerkt worden).

```bash
bash common/install-pm-cooldown.sh             # default 7 dagen
bash common/install-pm-cooldown.sh --days 14   # andere window
bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen
```

Idempotent en user-level (geen sudo). Schrijft naar:

| File              | Key                            | Eenheid  | Manager       |
|-------------------|--------------------------------|----------|---------------|
| `~/.npmrc`        | `min-release-age`              | dagen    | npm 11.10+    |
| `~/.npmrc`        | `minimum-release-age`          | minuten  | pnpm 10.16+   |
| `~/.bunfig.toml`  | `[install] minimumReleaseAge`  | seconden | bun 1.3+      |

Bestaande inhoud (auth tokens, registries, custom keys) en file-mode blijven
behouden. Voor een spoedige CVE-fix die binnen het venster valt: per-project
override via een lokale `.npmrc` / `bunfig.toml` met de waarde op `0`.

### Per-project + CI

`~/.npmrc` dekt alleen je eigen workstation. CI-runners draaien als een
andere user zonder dit home-config, dus de cooldown is daar bypassed —
precies waar supply-chain attacks in production builds landen. Drop
daarom een **project-lokale** config in elke Node/Bun repo die je owned:

```bash
cp common/templates/project-npmrc.example         <jouw-repo>/.npmrc
cp common/templates/project-bunfig.toml.example   <jouw-repo>/bunfig.toml
# committen — beide files bevatten geen secrets
```

Voor projecten waar je geen file mag committen (gedeeld met teams die
deze opinie niet delen): in plaats daarvan CI env vars zetten —
`NPM_CONFIG_MIN_RELEASE_AGE=7` en `NPM_CONFIG_MINIMUM_RELEASE_AGE=10080`.
Zie `common/templates/README.md` voor de volledige uitleg.

## Handmatige update

```bash
sudo bash common/update.sh
```

## WSL Support

De installer + checks zijn WSL-aware. Een WSL2-Ubuntu draait de gewone
`bootstrap.sh` → `ubuntu/install.sh`-flow; WSL2-Alma idem voor `alma/`.
Wat afwijkt op WSL:

| Component | Native Linux | WSL zonder systemd | WSL met systemd-opt-in |
|---|---|---|---|
| Package install (clamav, rkhunter) | ✓ | ✓ | ✓ |
| `install-pm-cooldown.sh` (user-level config) | ✓ | ✓ | ✓ |
| `install-shell-tools.sh` + pre-commit gates | ✓ | ✓ | ✓ |
| systemd timers (auto-scans) | ✓ | skipped + warning | ✓ |
| `check.sh` services/timers sectie | ✓ | skipped + WSL-uitleg | ✓ |
| `scan.sh` excludes `/mnt/*` (Windows drives) | n/a | auto | auto |
| `incident-token-revoke.sh` | ✓ Linux-side | ✓ Linux-side + Windows-warning | ✓ Linux-side + Windows-warning |

### WSL2 + systemd inschakelen (aanbevolen)

Zonder systemd kunnen de dagelijkse timers niet draaien. Eenmalige setup:

```bash
# In WSL2:
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF

# Vervolgens vanuit Windows PowerShell:
wsl --shutdown
# Open WSL opnieuw — controleer met:
ps -p 1 -o comm=    # moet 'systemd' zijn
```

Daarna draait `sudo bash bootstrap.sh` als op native Linux.

### WSL1 of WSL2 zonder systemd

Alles werkt behalve de timers. Voor automatische scans heb je twee opties:

1. **Migreer naar WSL2 met systemd** (zie boven) — aanbevolen.
2. **Handmatig draaien** wanneer je toch al in WSL zit:
   ```bash
   sudo bash common/update.sh    # wekelijks bv. via een cron alias
   sudo bash common/scan.sh
   sudo rkhunter --check
   ```

### Incident response op WSL — scope-limit

`incident-token-revoke.sh` detecteert WSL en print bij start een
waarschuwing dat **persistence op de Windows-host** (Task Scheduler, HKCU
Run-keys, startup folder) niet door dit script wordt gezien. Voor een
volledige IR op WSL controleer je óók Windows-kant — het script print de
exacte PowerShell + reg-commands die je daar moet draaien.

## Verwijderen

```bash
sudo bash common/uninstall.sh
```

Dit verwijdert de systemd timers en logrotate config. ClamAV en rkhunter packages blijven staan — verwijder die handmatig als gewenst.
