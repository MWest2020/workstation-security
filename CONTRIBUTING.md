# Contributing

workstation-security is een persoonlijk onderhouden project. Bijdragen zijn welkom, maar er is geen response-tijd-garantie en niet elke PR landt.

## Voor een goede PR

1. Test op je eigen distro (en idealiter één andere — dry-run via `bash bootstrap.sh --dry-run` werkt op elke distro zonder side effects).
2. `bash common/check-shell-headers.sh --all .` moet exit 0 geven.
3. `shellcheck -x` over je wijziging clean.
4. `CHANGELOG.md`-entry in de juiste sectie (`## Unreleased` → relevante categorie).
5. Hou de PR klein — één feature/fix per PR. Bundle alleen wanneer onlosmakelijk verbonden (zie OpenSpec changes onder `openspec/changes/` voor hoe gebundelde scope er uit ziet).

## Welke PRs landen makkelijk

- Bug-fixes met reproductie-stappen (gebruik [bug report-template](.github/ISSUE_TEMPLATE/bug_report.md)).
- Nieuwe distro-support (gebruik [distro support-template](.github/ISSUE_TEMPLATE/distro_support.md) om eerst overeenstemming te bereiken).
- Doc-verbeteringen.
- Tests, smoke-test-uitbreidingen, CI-hardening.

## Welke PRs landen lastig

- Scope-uitbreiding richting centrale EDR / log-aggregatie / fleet management. Dit project blijft expliciet workstation-only — zie [`docs/threat-model.md`](docs/threat-model.md) → "Out of scope".
- Wijzigingen die nieuwe runtime-dependencies introduceren zonder concrete bug/feature-justification.
- Refactors zonder een concreet probleem dat ze oplossen.
- Wijzigingen die de drie verdedigingslagen door-elkaar-husselen of moeilijker apart te begrijpen maken — elk van AV/cooldown/IR moet standalone uitlegbaar blijven.

## Stijl

- Shell: Google Shell Style + repo-conventies (zie `common/check-shell-headers.sh` voor wat er afgedwongen wordt).
- Shebang: `#!/usr/bin/env bash` (macOS-portable).
- SPDX-header: `# SPDX-License-Identifier: EUPL-1.2` in eerste 5 regels.
- `# role:` marker: `entrypoint`, `library`, `container-entrypoint`, `installer`, of `tool`.
- `set -euo pipefail` voor `entrypoint` / `installer` (libraries laten de caller bepalen).
- Comments: leg de *waarom* uit, niet de *wat*. Audit-relevante keuzes verdienen een paragraaf.
- Nederlandse tekst in user-facing output mag — consistent met de bestaande baseline.

## Spec-driven changes (OpenSpec)

Voor niet-triviale wijzigingen werken we via OpenSpec changes in `openspec/changes/<change-name>/`. Een change bevat:

- `proposal.md` — Why / What / Capabilities / Impact.
- `tasks.md` — concrete checkboxes per cluster.
- `specs/<capability>/spec.md` — requirements met scenarios.
- `design.md` — alleen wanneer een ontwerpkeuze niet vanzelfsprekend is en gedocumenteerd moet kunnen worden voor een latere lezer / auditor.

Validatie: `openspec validate <change-name> --strict` moet groen zijn voordat de change archived wordt. De [OpenSpec CLI](https://github.com/Fission-AI/OpenSpec) installeer je via `npm i -g @fission-ai/openspec`.

## License

Door een PR in te dienen ga je akkoord dat je bijdrage onder dezelfde [EUPL-1.2](LICENSE) wordt vrijgegeven die de rest van het project gebruikt. Geen CLA, geen overdracht van rechten — je behoudt copyright op je bijdrage en licentieert hem onder EUPL-1.2.
