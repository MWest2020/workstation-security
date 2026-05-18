# smoke-tests Specification

## Purpose
TBD - created by archiving change v1-release-readiness. Update Purpose after archive.
## Requirements
### Requirement: GitHub Actions smoke-test matrix
De repo SHALL een GitHub Actions workflow bevatten (`.github/workflows/smoke.yml`) die op elke `push` en `pull_request` smoke-tests MUST draaien in een matrix over de drie ondersteunde distrofamilies (alma9, ubuntu2404, archlatest) via Docker.

#### Scenario: Workflow triggers
- **WHEN** een commit wordt gepusht naar de repo of een pull request wordt geopend
- **THEN** de `smoke` workflow start automatisch voor elk van de drie matrix-distros

#### Scenario: Smoke-stappen per distro
- **WHEN** de workflow draait voor een distro
- **THEN** het start een Docker-container van de bijbehorende publieke image (`almalinux:9`, `ubuntu:24.04`, `archlinux:latest`), mount de checkout op `/repo`, en draait sequentieel: `bash bootstrap.sh --dry-run` (moet exit 0) en daarna `bash check.sh` (mag exit 0, 1, of 2)

#### Scenario: Geen side effects op CI-runner
- **WHEN** de workflow draait
- **THEN** alle baseline-scripts draaien in `--dry-run` (resp. read-only voor `check.sh`); er worden geen pakketten geïnstalleerd op de container die naar buiten lekken (de container is ephemeral) en geen workflow-stap schrijft naar de host runner

### Requirement: CI-status zichtbaar in README
De README SHALL CI-badges bovenaan tonen zodat externe lezers de status van de smoke-tests én andere relevante checks (shellcheck) in één oogopslag MUST kunnen zien.

#### Scenario: README-badges
- **WHEN** een lezer de README bekijkt op GitHub
- **THEN** ziet hij bovenaan minimaal een shellcheck-badge en een smoke-badge die de huidige status van die workflows reflecteren

### Requirement: Rolling-image pinning bij upstream-breuk
Wanneer een matrix-image rolling is (`archlinux:latest`) en CI breekt door een upstream-wijziging die niets met deze repo te maken heeft, MAY de workflow de image pinnen op een specifieke tag. Zo'n pin MUST gedocumenteerd zijn in een comment naast de pin, en er SHALL een follow-up issue aangemaakt worden om de pin op te ruimen wanneer upstream weer stabiel is.

#### Scenario: Arch image breekt CI
- **WHEN** `archlinux:latest` een upstream-wijziging krijgt waardoor `bash bootstrap.sh --dry-run` faalt zonder repo-wijziging
- **THEN** de matrix-entry mag gepind worden (bv. `archlinux:base-20260501`), met een comment `# pinned 2026-XX-XX wegens <reden>` op die regel, en een follow-up issue om de pin op te ruimen wanneer upstream stabiel is

