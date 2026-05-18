## 1. A2 — Cooldown-doc-split

- [x] 1.1 Schrijf `docs/supply-chain-cooldown.md` (~600-800 woorden): aanleiding (npm-incident 2026-05-11), mechanisme per package-manager met versie-vereisten, per-workstation vs per-project vs CI-gap, override-flow voor urgente CVEs, links naar `common/install-pm-cooldown.sh` + templates
- [x] 1.2 Verkort README-sectie 2 (drie verdedigingslagen → cooldown) tot 3-4 zinnen met link naar de nieuwe doc
- [x] 1.3 Voeg `docs/supply-chain-cooldown.md` toe aan de index-tabel in `docs/README.md`
- [ ] 1.4 Doc-review: lees de nieuwe doc cold; zou een lezer zonder context het mechanisme en de overrides begrijpen?

## 2. C1 — Versioning

- [x] 2.1 Voeg top-level `VERSION`-file toe met `0.9.0`
- [x] 2.2 Implementeer `ws_version()` helper in `common/lib.sh` (leest `VERSION` relatief aan `BASH_SOURCE`, fallback `unknown`)
- [x] 2.3 Voeg `--version` / `-V` flag toe aan `bootstrap.sh` met early exit voor OS-detectie
- [x] 2.4 Voeg `--version` / `-V` flag toe aan `check.sh`
- [x] 2.5 Voeg `--version` / `-V` flag toe aan elke `common/*.sh` met user-facing CLI (`install-pm-cooldown.sh`, `install-shell-tools.sh`, `incident-token-revoke.sh`, `scan.sh`, `rkhunter-check.sh`, `update.sh`, `uninstall.sh`)
- [ ] 2.6 Schrijf bats-test: `bash bootstrap.sh --version` print de version-string en exit 0 (handmatige smoke gedaan; bats-suite nog niet opgezet — apart van deze change)
- [x] 2.7 Edge-case test: tijdelijke rename van `VERSION` → `ws_version()` returnt `unknown`, script werkt door (handmatig geverifieerd)

## 3. C2 — CI-matrix

- [x] 3.1 Schrijf `.github/workflows/smoke.yml` met matrix (`alma9`, `ubuntu2404`, `archlatest`) en stappen: checkout, `bash bootstrap.sh --dry-run` (depends op C5), `bash check.sh` (exit ≤ 2)
- [x] 3.2 Map matrix-strings → Docker-image-namen (`almalinux:9`, `ubuntu:24.04`, `archlinux:latest`) in workflow-script
- [x] 3.3 Voeg CI-badges (smoke + license + shellcheck) bovenaan README toe; molecule-badge nog niet — B2 bestaat niet
- [ ] 3.4 Eerste workflow-run draaien op een PR en groen krijgen; bij Arch-breuk image pinnen + comment met reden (handmatige stap zodra er gepusht wordt)
- [ ] 3.5 (Conditional) Schrijf `.github/workflows/ansible-molecule.yml` met `paths: ansible/**` trigger — alleen als B2 (ansible-bootstrap) al bestaat

## 4. C3 + C4 — Repo-hygiene + README-restructuring

- [x] 4.1 Voeg `LICENSE` toe met de volledige EUPL-1.2-tekst (van SPDX license-list-data — canonieke bron)
- [x] 4.2 Schrijf `CONTRIBUTING.md` (project-status, "voor een goede PR", "welke PRs landen makkelijk/lastig", OpenSpec-workflow)
- [x] 4.3 Voeg `.github/ISSUE_TEMPLATE/bug_report.md` toe (distro, versie via `bootstrap.sh --version`, output van `check.sh`, reproductie)
- [x] 4.4 Voeg `.github/ISSUE_TEMPLATE/distro_support.md` toe (distro, package-manager, `/etc/os-release` ID/ID_LIKE, bereidheid tot testing)
- [x] 4.5 Voeg `.github/ISSUE_TEMPLATE/config.yml` toe met `blank_issues_enabled: false`
- [x] 4.6 Update README clone-URL `conduction-it/` → `MWest2020/`
- [x] 4.7 Herstructureer README: intro → doelgroep/scope (gepromoveerd) → drie verdedigingslagen (elk eigen H2 met "wat", "voor wie", "snelle start") → installatie → check → IR → WSL → docs-links
- [x] 4.8 Voeg `## License`-sectie onderaan README toe met EUPL-1.2-motivatie (digitale soevereiniteit, NLnet-context)
- [ ] 4.9 Doc-review: nieuwe lezer kan in 60s zien of dit voor hem relevant is en welke license/contributing-policy geldt

## 5. C5 — `--dry-run` op installers

- [x] 5.1 Voeg `--dry-run` flag toe aan `bootstrap.sh`; print `Would dispatch to: <sub>/install.sh` + `(dry-run; no changes made)`, exit 0
- [x] 5.2 Voeg `--dry-run` flag toe aan `alma/install.sh`; print `dnf install` commando('s) + verwijzing naar `install-timers` aanroep, exit 0
- [x] 5.3 Idem voor `arch/install.sh` (`pacman -Syu`)
- [x] 5.4 Idem voor `ubuntu/install.sh` (`apt install`)
- [x] 5.5 Voeg `--dry-run` flag toe aan `common/install-timers.sh`; print unit-file-inhoud naar stdout in plaats van `/etc/systemd/system/`
- [x] 5.6 Voeg `--dry-run` flag toe aan `common/install-pm-cooldown.sh`; print config-wijzigingen zonder `~/.npmrc` / `~/.bunfig.toml` aan te raken (hergebruik logica uit `--check`)
- [x] 5.7 Implementeer propagatie: `bootstrap.sh` zet `WS_DRY_RUN=1` in environment bij dispatch; sub-installers respecteren zowel `--dry-run` als `WS_DRY_RUN=1` (helpers `ws_is_dry_run` en `ws_run_or_print` in `lib.sh`)
- [ ] 5.8 CI-smoke (3.1) draait `bootstrap.sh --dry-run` op alle drie distros en bevestigt: geen pakketten geïnstalleerd, exit 0 (workflow geschreven, eerste run komt zodra gepusht)

## 6. C6 — v1.0.0 release

- [ ] 6.1 Voorwaarde: alle A+B+C-PR's gemerged, CI groen, geen openstaande blokkers
- [ ] 6.2 Update `VERSION` → `1.0.0`
- [ ] 6.3 CHANGELOG-entry onder `## v1.0.0 (YYYY-MM-DD)` met geconsolideerde samenvatting van A+B+C
- [ ] 6.4 Merge PR `chore: release v1.0.0`
- [ ] 6.5 `git tag -a v1.0.0 -m "v1.0.0 — initial public release"`
- [ ] 6.6 `git push origin v1.0.0`
- [ ] 6.7 GitHub Release aanmaken via `gh release create v1.0.0` met title + CHANGELOG-fragment als body
- [ ] 6.8 Blogpost-draft (1500-2500 woorden): incident → drie lagen → keuzes → out-of-scope → repo-link → license; link naar `tree/v1.0.0` (niet `main`)
- [ ] 6.9 Cross-post overwegen (dev.to / LinkedIn / HN / r/devops afhankelijk van timing)
- [ ] 6.10 Externe lezer (collega buiten Conduction) vragen in 5 min te zeggen waar het project over gaat en of 'ie het zou oppakken; feedback verwerken in eventuele v1.0.1

## 7. Definition of Done v1.0.0

- [ ] 7.1 Alle bullet-points uit `proposal.md` → "Success criteria" (indien aanwezig in upstream proposal) afgevinkt
- [ ] 7.2 GitHub Release zichtbaar op `github.com/MWest2020/workstation-security/releases`
- [ ] 7.3 Blogpost gepubliceerd en gelinkt vanuit de Release-notes
- [ ] 7.4 README CI-badges groen
- [ ] 7.5 Tag `v1.0.0` aanwezig in repo en pointer correct (`git rev-parse v1.0.0`)
