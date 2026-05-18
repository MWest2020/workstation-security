# workstation-security

[![smoke](https://github.com/MWest2020/workstation-security/actions/workflows/smoke.yml/badge.svg)](https://github.com/MWest2020/workstation-security/actions/workflows/smoke.yml)
[![License: EUPL-1.2](https://img.shields.io/badge/License-EUPL_1.2-blue.svg)](LICENSE)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen)](.pre-commit-config.yaml)

Lichtgewicht baseline voor het hardenen van developer workstations. Bedoeld om de minimale set verdedigingen op orde te hebben die je voor een ISO 27001 / SOC 2 / NEN 7510 / BIO audit moet kunnen aantonen, zonder een full-blown EDR uit te rollen.

Voor mappings naar specifieke control-IDs en het bedreigingsmodel: zie [`docs/`](docs/) — `compliance.md` voor de framework-mapping, `threat-model.md` voor wat we wel/niet verdedigen, `supply-chain-cooldown.md` voor de standalone uitleg van laag 2.

## Doelgroep en scope

- Developer workstations, **niet** servers — de aanname is dat de user grotendeels root is op z'n eigen machine en de defaults wil kunnen uitleggen aan een auditor.
- Target distros: Alma / Rocky / RHEL / Fedora / CentOS (dnf), Arch / Manjaro / EndeavourOS (pacman), Ubuntu / Debian / Mint / Pop / Raspbian (apt). macOS wordt deels ondersteund — het IR-script werkt cross-platform.
- WSL2 (Windows Subsystem for Linux) is detecteerbaar en wordt netjes afgehandeld — scripts skippen systemd-features waar nodig in plaats van hard te falen. Zie [WSL Support](#wsl-support) onderaan.

## Drie verdedigingslagen

Elk standalone te begrijpen en in te zetten. Je kunt 1, 2 en 3 los gebruiken — `bootstrap.sh` rolt 1 uit (de andere zijn aparte invocations).

### 1. Antivirus + rootkit

**Wat:** ClamAV (dagelijkse scan van `/home`) en rkhunter (rootkit check), via systemd timers. Bij vondsten een `wall`-melding aan ingelogde users. Logs geroteerd via logrotate (wekelijks, 4 weken bewaard).

**Voor wie:** elke auditor en elk compliance-framework wil *iets* aan AV zien op een workstation, ook al is het bedreigingsmodel voor klassieke virussen op dev-machines beperkt. Dit dekt die eis met minimal overhead.

**Snelle start:**
```bash
sudo bash bootstrap.sh             # auto-detect OS, installeert AV + timers
sudo bash check.sh                 # exit-code = aantal problemen (cron/CI-bruikbaar)
```

Na installatie:

| Timer                    | Wanneer         | Wat                             |
|--------------------------|-----------------|----------------------------------|
| `av-update.timer`        | Dagelijks 04:00 | Signatures + rkhunter database  |
| `clamav-scan.timer`      | Dagelijks 02:00 | Volledige scan van `/home`      |
| `rkhunter-check.timer`   | Dagelijks 03:00 | Rootkit check                   |

### 2. Supply-chain cooldown (npm / pnpm / bun)

**Wat:** 7-daagse quarantine op verse pakketversies. npm yankt malicious supply-chain versies doorgaans binnen 24-48u — een cooldown houdt ze buiten je lockfile vóór ze opgemerkt worden.

**Voor wie:** iedereen die `npm install` / `pnpm install` / `bun install` op een dev-machine of in CI draait. Vooral relevant als je projecten met veel transitive deps onderhoudt.

**Snelle start:**
```bash
bash common/install-pm-cooldown.sh             # default 7 dagen
bash common/install-pm-cooldown.sh --days 14   # andere window
bash common/install-pm-cooldown.sh --check     # huidige state tonen
bash common/install-pm-cooldown.sh --dry-run   # wat het zou doen, geen wijzigingen
```

User-level (`~/.npmrc` + `~/.bunfig.toml`). Voor CI / per-project / override-flow zie [`docs/supply-chain-cooldown.md`](docs/supply-chain-cooldown.md).

### 3. Incident response — GitHub-token compromise

**Wat:** losse IR-tool voor het CanisterSprawl-scenario (gestolen GitHub-PAT met dead-man's switch die `rm -rf ~/` triggert wanneer je 'm probeert te revoken). Detecteert, ontwapent veilig (SIGKILL-first, evidence buiten `$HOME`), en wacht op handmatige revoke met verify.

**Voor wie:** als je `gh` CLI gebruikt of een GitHub PAT in je shell hebt en het scenario klinkt niet hypothetisch genoeg om te negeren. Bij twijfel: draai eerst `--dry-run` om te zien of de detectie iets vindt.

**Snelle start:**
```bash
bash common/incident-token-revoke.sh --dry-run   # alleen detectie
bash common/incident-token-revoke.sh             # volledige flow
```

User-level (geen root nodig). Schone runs laten niks achter op disk; alleen bij findings wordt `/tmp/incident-<ts>/` aangemaakt. Voor optionele mail-rapportage via SMTPS zie de "Optionele mail-rapportage"-sectie verderop.

## Installatie

Clone en installeer in één keer.

```bash
git clone https://github.com/MWest2020/workstation-security.git
cd workstation-security
sudo bash bootstrap.sh
```

`bootstrap.sh` leest `/etc/os-release` en dispatched naar de juiste installer (alma/arch/ubuntu). Bij onbekend OS valt het terug op `ID_LIKE` en print anders een heldere foutmelding.

Direct per-OS installer kan ook:

```bash
sudo bash alma/install.sh             # Alma / Rocky / CentOS / RHEL / Fedora
sudo bash arch/install.sh             # Arch / Manjaro / EndeavourOS
sudo bash ubuntu/install.sh           # Ubuntu / Debian / Mint / Pop / Raspbian
```

Voor CI / audit-evidence-flows: elk van bovenstaande accepteert `--dry-run`. Geen side effects, exit 0, output copy-paste-baar.

```bash
sudo bash bootstrap.sh --dry-run      # print welke sub-installer aangeroepen zou worden
bash ubuntu/install.sh --dry-run      # print zou-uitgevoerd-zijn pkg-manager commando's
```

`--version` werkt op alle entrypoints en respecteert geen sudo:

```bash
bash bootstrap.sh --version           # workstation-security <semver>
```

## Status check

```bash
sudo bash check.sh
```

Toont services / timers / signatures / laatste scans. Exit-code is gelijk aan het aantal gevonden problemen (capped op 2), zodat het in cron of CI gebruikt kan worden als gezondheids-probe.

## Handmatige scan + update

```bash
sudo clamscan -r /home --infected --log=/var/log/clamav/manual-scan.log
sudo rkhunter --check --skip-keypress
sudo bash common/update.sh            # signatures + rkhunter db
```

## Incident response — uitgebreid

Het IR-script (`common/incident-token-revoke.sh`) vangt eerst de huidige `gh`-token op (hash + last-4) voor latere verify, detecteert IOC's + heuristisch, kill't polling-processen met **SIGKILL voordat** systemd er een SIGTERM op stuurt (een TERM-trap in de payload kan namelijk alsnog `rm -rf ~/` triggeren), archiveert artefacten naar `/tmp/incident-<ts>/` (overleeft `rm -rf ~/`), maakt de token op deze machine onbruikbaar, en wacht op handmatige revoke op github.com/settings/tokens (er is geen user-self-revoke REST endpoint).

### Optionele mail-rapportage

Standaard blijft alles lokaal. Voor een SMTPS-mail (bv. Gmail) na afloop:

```bash
mkdir -p ~/.config/workstation-security
cp common/incident-token-revoke.env.example ~/.config/workstation-security/mail.env
chmod 600 ~/.config/workstation-security/mail.env
$EDITOR ~/.config/workstation-security/mail.env
```

Het script weigert te mailen als die file niet op mode 600/400 staat (bevat een App Password).

## WSL Support

De installer + checks zijn WSL-aware. Een WSL2-Ubuntu draait de gewone `bootstrap.sh` → `ubuntu/install.sh`-flow; WSL2-Alma idem voor `alma/`. Wat afwijkt op WSL:

| Component | Native Linux | WSL zonder systemd | WSL met systemd-opt-in |
|---|---|---|---|
| Package install (clamav, rkhunter) | ✓ | ✓ | ✓ |
| `install-pm-cooldown.sh` (user-level config) | ✓ | ✓ | ✓ |
| `install-shell-tools.sh` + pre-commit gates | ✓ | ✓ | ✓ |
| systemd timers (auto-scans) | ✓ | skipped + warning | ✓ |
| `check.sh` services/timers sectie | ✓ | skipped + WSL-uitleg | ✓ |
| `scan.sh` ClamAV scan op `/home` | ✓ | ✓ (handmatig) | ✓ (via timer) |
| `scan.sh` excludes `/mnt/*` (Windows drives) | n/a | auto | auto |
| `rkhunter-check.sh` rootkit-check | ✓ | skipped (bewust) | skipped (bewust) |
| `incident-token-revoke.sh` Linux-side | ✓ | ✓ + Windows-warning | ✓ + Windows-warning |
| `incident-token-revoke.sh` clipboard/URL-open | wl-copy/xclip/pbcopy | clip.exe + wslview/cmd.exe | clip.exe + wslview/cmd.exe |

**Waarom rkhunter op WSL bewust uit?** Op WSL geeft `rkhunter --check` veel false-positives (proc-checks, passwd-checks rond WSL's init-proces, en `system_configs.t` verwacht echte init-scripts). Een daily wall-melding met onbetrouwbare waarschuwingen leidt tot alarm-fatigue, wat op zichzelf al een ISO 27001-bevinding is ("medewerkers negeren security-alerts"). WSL's container-achtige isolatie verandert sowieso het rootkit-bedreigings-model — de Windows-host is daar de relevante verdedigingslaag (Defender / EDR). `rkhunter-check.sh` detecteert WSL en exit 0 met uitleg; de timer fired wel maar produceert geen wall-spam.

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

`incident-token-revoke.sh` detecteert WSL en print bij start een waarschuwing dat **persistence op de Windows-host** (Task Scheduler, HKCU Run-keys, startup folder) niet door dit script wordt gezien. Voor een volledige IR op WSL controleer je óók Windows-kant — het script print de exacte PowerShell + reg-commands die je daar moet draaien.

## Verwijderen

```bash
sudo bash common/uninstall.sh
```

Dit verwijdert de systemd timers en logrotate config. ClamAV en rkhunter packages blijven staan — verwijder die handmatig als gewenst.

## Verder lezen

| Doc | Voor wie |
|-----|----------|
| [`docs/compliance.md`](docs/compliance.md) | Auditor, security officer, sales-ondersteuning — control-mapping naar ISO 27001 / SOC 2 / NEN 7510 / BIO. |
| [`docs/threat-model.md`](docs/threat-model.md) | Implementatie-engineers, security-reviewers — wat we wel/niet verdedigen. |
| [`docs/supply-chain-cooldown.md`](docs/supply-chain-cooldown.md) | Devs die alleen laag 2 willen begrijpen of adopteren. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Iedereen die een PR overweegt. |
| [`openspec/`](openspec/) | Spec-driven changes — `proposal.md` + `tasks.md` + spec-deltas per change. |

## License

[EUPL-1.2](LICENSE) — European Union Public Licence v. 1.2.

EUPL is OSI-approved, vrije software-licentie en breed gedragen in Europese publieke-sector projecten. De keuze is bewust: deze repo komt voort uit werk rond digitale soevereiniteit en NLnet-gesponsorde projecten, waar EUPL het natuurlijke pad is voor permissive sharing zonder afhankelijkheid van een US-juridisch kader. Compatible met de meeste copyleft- en permissive licenties (inclusief GPL, AGPL, MIT en Apache-2.0) voor afgeleide werken.

SPDX-headers in elke source-file (`# SPDX-License-Identifier: EUPL-1.2`) maken de licentie machine-leesbaar voor SBOM-tools.
