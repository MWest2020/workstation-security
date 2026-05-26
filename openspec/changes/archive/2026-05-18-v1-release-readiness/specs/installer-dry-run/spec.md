## ADDED Requirements

### Requirement: `--dry-run` op installer-entrypoints
De installer-entrypoints (`bootstrap.sh`, `alma/install.sh`, `arch/install.sh`, `ubuntu/install.sh`, `common/install-timers.sh`, `common/install-pm-cooldown.sh`) SHALL `--dry-run` accepteren. Met die flag MUST ze geen side effects uitvoeren (geen pakket-installaties, geen schrijven naar `/etc/systemd/system/` of `~/.npmrc` of `~/.bunfig.toml`) en SHALL ze printen wat ze gedaan zouden hebben.

#### Scenario: bootstrap.sh --dry-run
- **WHEN** een gebruiker `sudo bash bootstrap.sh --dry-run` draait
- **THEN** het script detecteert het OS via `/etc/os-release`, print `Would dispatch to: <sub>/install.sh` plus de regel `(dry-run; no changes made)`, en exit 0 — zonder de sub-installer aan te roepen

#### Scenario: per-OS installer --dry-run
- **WHEN** een gebruiker `sudo bash alma/install.sh --dry-run` (of arch/ubuntu equivalent) draait
- **THEN** het script print de pakket-manager-commando's die het zou draaien (bv. `dnf install -y clamav rkhunter ...`) plus de install-timers-aanroep die zou volgen, en exit 0 — zonder pakketten te installeren of timers te schrijven

#### Scenario: install-timers.sh --dry-run
- **WHEN** `bash common/install-timers.sh --dry-run` draait
- **THEN** het script print de inhoud van elk unit-file (service + timer) naar stdout in plaats van te schrijven naar `/etc/systemd/system/`, voert geen `systemctl daemon-reload` of `systemctl enable` uit, en exit 0

#### Scenario: install-pm-cooldown.sh --dry-run
- **WHEN** een gebruiker `bash common/install-pm-cooldown.sh --dry-run` draait
- **THEN** het script print de config-wijzigingen die het zou toepassen op `~/.npmrc` en `~/.bunfig.toml`, raakt die files niet aan, en exit 0. Logica mag hergebruikt worden uit de bestaande `--check` mode

### Requirement: Dry-run propagatie via env-var
`bootstrap.sh` SHALL de dry-run-modus doorgeven aan zijn sub-installers via de env-var `WS_DRY_RUN=1`. Sub-installers MUST zowel de eigen `--dry-run` flag als `WS_DRY_RUN=1` uit de environment respecteren.

#### Scenario: bootstrap propageert WS_DRY_RUN
- **WHEN** `sudo bash bootstrap.sh --dry-run` draait op een Ubuntu-systeem
- **THEN** als de dispatch tóch zou plaatsvinden (in de toekomstige variant waarin bootstrap delegeert in plaats van zelf te short-circuiten), `ubuntu/install.sh` ontvangt `WS_DRY_RUN=1` in zijn environment en gedraagt zich identiek aan `bash ubuntu/install.sh --dry-run`

#### Scenario: Sub-installer leest WS_DRY_RUN
- **WHEN** een gebruiker `WS_DRY_RUN=1 bash alma/install.sh` draait (zonder `--dry-run` flag)
- **THEN** de installer voert geen side effects uit en gedraagt zich identiek aan `bash alma/install.sh --dry-run`
