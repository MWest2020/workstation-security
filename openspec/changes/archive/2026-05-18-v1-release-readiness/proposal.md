## Why

De repo is in praktische zin compleet (drie verdedigingslagen werken, WSL-aware, audit-docs aanwezig), maar mist de signalen die een externe lezer in 60 seconden vertrouwen geven: een herkenbare licentie, CI-badges, een releasebare versie, en een duidelijke "wat is dit" bovenaan de README. Daarnaast is de supply-chain cooldown een uniek verkooppunt dat verstopt zit in sectie 2 van een drielagig verhaal, en hebben de installers geen dry-run-modus waardoor CI/audit-evidence-flows ze niet kunnen draaien.

Deze change bundelt zeven kleinere clusters (A2 + C1-C6) tot één coherent v1.0.0-leveringspakket, omdat elk afzonderlijk te dun is voor een eigen change maar samen wel het v1.0.0-tag rechtvaardigen.

## What Changes

- **A2** — `docs/supply-chain-cooldown.md` toegevoegd; README-sectie 2 verkort tot 3-4 zinnen + link.
- **C1** — `VERSION`-file als single source of truth; `ws_version()` in `common/lib.sh`; `--version`/`-V` flag op alle user-facing entrypoints (`bootstrap.sh`, `check.sh`, alle `common/*.sh`-CLIs).
- **C2** — `.github/workflows/smoke.yml` met matrix (alma9, ubuntu2404, archlatest); CI-badges in README.
- **C3+C4** — `LICENSE` (volledige EUPL-1.2), `CONTRIBUTING.md`, GitHub issue templates (bug / distro-support / config); README herstructureerd (intro → scope → drie lagen met eigen H2 → installatie → check → IR → WSL → docs); clone-URL gecorrigeerd naar `MWest2020/`.
- **C5** — `--dry-run` flag op `bootstrap.sh`, `alma/install.sh`, `arch/install.sh`, `ubuntu/install.sh`, `common/install-timers.sh`, `common/install-pm-cooldown.sh`. Flag propageert via `WS_DRY_RUN=1` env-var. Geen side effects in dry-run; exit 0 bij happy path.
- **C6** — `VERSION` → `1.0.0`, CHANGELOG-entry, git tag `v1.0.0`, GitHub Release, blogpost-draft. Pas uitvoeren als A+B+C-PR's gemerged en CI groen.

Geen **BREAKING** wijzigingen: bestaande aanroepen blijven werken; `--version` / `--dry-run` zijn opt-in flags, `VERSION`-file ontbrekend levert "unknown" (geen exit 2).

## Capabilities

### New Capabilities

- `versioning`: alle entrypoints rapporteren hun versie uit één bron van waarheid (`VERSION`-file), bereikbaar via `--version`/`-V` flag en een `ws_version()` helper.
- `installer-dry-run`: installers ondersteunen `--dry-run` om in CI en audit-evidence-flows zonder side effects gedraaid te worden; flag propageert automatisch van `bootstrap.sh` naar sub-installers via `WS_DRY_RUN`.
- `smoke-tests`: een CI-matrix draait op elke push/PR een `bootstrap.sh --dry-run` + `check.sh` smoke-test op de drie ondersteunde distrofamilies (alma, ubuntu, arch) zodat regressies in OS-detectie of installer-structuur direct zichtbaar zijn.

### Modified Capabilities

Geen — er bestaan nog geen specs in `openspec/specs/`; dit is de eerste change die capabilities introduceert.

## Impact

- **Code** — `common/lib.sh` (helper toegevoegd), zes script-entrypoints (flag-parsing toegevoegd), één nieuwe top-level file (`VERSION`).
- **Docs** — README aanzienlijk herschreven; nieuwe `docs/supply-chain-cooldown.md`; `docs/README.md` index uitgebreid; `CONTRIBUTING.md` en `LICENSE` toegevoegd.
- **CI** — eerste GitHub Actions workflows in deze repo; vereist `.github/workflows/` directory.
- **Dependencies** — geen runtime-deps; CI gebruikt publieke Docker-images (`almalinux:9`, `ubuntu:24.04`, `archlinux:latest`).
- **Externe surface** — clone-URL in README wijzigt van `conduction-it/` naar `MWest2020/`; lezers van eerdere README zien een 404 op de oude URL maar de repo zelf is openbaar onder de nieuwe org.
- **Release** — eerste getagde versie van de repo (`v1.0.0`); na C6 hangt de blogpost en eventuele cross-posts hieraan.
