# versioning Specification

## Purpose
TBD - created by archiving change v1-release-readiness. Update Purpose after archive.
## Requirements
### Requirement: Single source of truth voor versie
De repo SHALL een top-level `VERSION`-file bevatten met één regel die de semver-versie van het project bevat. Alle entrypoints die hun versie tonen MUST die lezen uit deze file via de helper `ws_version()`.

#### Scenario: VERSION-file leesbaar
- **WHEN** een entrypoint `ws_version()` aanroept en `VERSION` bestaat en is leesbaar
- **THEN** de helper print de inhoud van `VERSION` (zonder trailing newline-handling-issue) naar stdout en exit 0

#### Scenario: VERSION-file ontbreekt of niet leesbaar
- **WHEN** een entrypoint `ws_version()` aanroept en `VERSION` ontbreekt of is niet leesbaar
- **THEN** de helper print `unknown` naar stdout en exit 0; het aanroepende script gaat door zonder fatale fout

### Requirement: `--version` / `-V` flag op user-facing entrypoints
Elk user-facing entrypoint (`bootstrap.sh`, `check.sh`, en elke `common/*.sh` met user-facing CLI: `install-pm-cooldown.sh`, `install-shell-tools.sh`, `incident-token-revoke.sh`, `scan.sh`, `rkhunter-check.sh`, `update.sh`, `uninstall.sh`) SHALL `--version` en `-V` accepteren als argument en MUST een version-string printen wanneer een van die flags aanwezig is.

#### Scenario: --version op bootstrap.sh
- **WHEN** een gebruiker `bash bootstrap.sh --version` draait
- **THEN** het script print `workstation-security <semver>` (waar `<semver>` de inhoud van `VERSION` is, of `unknown`) en exit 0 zonder OS-detectie of dispatch uit te voeren

#### Scenario: -V als alias
- **WHEN** een gebruiker `bash check.sh -V` draait
- **THEN** het gedrag is identiek aan `--version`: print version-string en exit 0

#### Scenario: --version vóór andere flags
- **WHEN** een gebruiker `--version` combineert met andere flags (bv. `bash install-pm-cooldown.sh --version --days 14`)
- **THEN** `--version` heeft voorrang; het script print de version-string en exit 0 zonder de andere flags te verwerken

