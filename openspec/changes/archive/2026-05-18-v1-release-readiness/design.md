## Context

Deze change bundelt zeven kleine clusters (A2 + C1-C6) richting een v1.0.0-tag. De meeste keuzes zijn vanzelfsprekend (toevoegen van een LICENSE-file, README-restructuring, issue-templates). Een paar zijn dat niet, en die leggen we hier vast — een auditor of latere lezer moet kunnen reconstrueren *waarom* deze variant en niet de net-zo-redelijke andere.

Leidend principe: kies de saaiste, audit-best-verdedigbare, KISS-conforme variant die breed gedragen wordt door de community. Wanneer twee opties allebei redelijk zijn, kies degene die het minst verbergt voor een lezer die de repo voor het eerst opent.

## Goals / Non-Goals

**Goals:**
- v1.0.0 kunnen taggen zonder dat een externe lezer hoeft te raden naar license, status, of "wat is dit eigenlijk".
- CI als objectief vertrouwen-signaal (badge groen of niet).
- Installers veilig kunnen draaien in CI / audit-evidence-flows zonder root of system state te raken.

**Non-Goals:**
- Geen scope-uitbreiding naar centrale EDR / log-aggregatie / fleet management — blijft expliciet buiten v1.0.0 conform `docs/threat-model.md`.
- Geen build-systeem of release-automatie naast wat GitHub Actions van zichzelf biedt; geen semantic-release-bot, geen changelog-generator.
- Geen wijziging aan de drie verdedigingslagen zelf (AV, cooldown, IR) — alleen aan de presentatie en runnability.

## Decisions

### D1. VERSION-file lezen at-runtime, niet embedden

**Keuze:** `common/lib.sh` leest de top-level `VERSION`-file via `BASH_SOURCE` op het moment dat `ws_version()` aangeroepen wordt. Geen build-step, geen sed-substitutie bij release.

**Alternatieven:**
- *Build-time substitutie* (bv. `sed -i "s/__VERSION__/$(cat VERSION)/" *.sh` in een release-script): vereist een build-stap waar er nu geen is.
- *Hard-coded constant in `lib.sh`*: extra plek om bij elke release te updaten; vergeet-risico.

**Waarom deze:** boring, KISS, geen build-pijplijn nodig. Past bij hoe de repo nu werkt (`git clone && bash bootstrap.sh`). Auditable: één file, één regel, `cat VERSION` op de host bewijst de versie. De fallback `unknown` zorgt dat een gebruiker die alleen een individueel script downloadt (zonder repo-context) geen crash krijgt.

### D2. `--dry-run` propageert via env-var **én** flag

**Keuze:** `bootstrap.sh` zet `WS_DRY_RUN=1` in environment *en* respecteert `--dry-run` als argument. Sub-installers lezen beide.

**Alternatieven:**
- *Alleen flag forwarding* (`bash "$installer" --dry-run`): werkt, maar als een sub-installer een toekomstige derde wrapper aanroept moet die de flag opnieuw forwarden. Brittle bij groei.
- *Alleen env-var*: minder ontdekbaar — een gebruiker die rechtstreeks `bash alma/install.sh` draait verwacht `--dry-run` als flag, niet een env-var.

**Waarom deze:** beide-werkt is een breed gedragen patroon (`NO_COLOR`, `CI`, `DEBIAN_FRONTEND`, `MAKEFLAGS`). De flag is voor mensen, de env-var is voor scripts en dispatch-ketens. Auditor ziet in elk script één parse-block dat beide checkt — geen verstopte magie.

### D3. Dry-run output gaat naar stdout, niet naar log of file

**Keuze:** Wat een installer "zou doen" wordt naar stdout geprint in een vorm die direct copy-paste-baar is naar een echte run (commando per regel, geen banner-decoraties die je moet weglaten).

**Alternatieven:**
- *JSON/yaml structured output*: handig voor tools, maar overkill voor wat een mens of een audit-evidence-screenshot moet kunnen lezen.
- *Schrijven naar `/tmp/dry-run-<ts>.log`*: extra cleanup; minder transparant in CI-logs.

**Waarom deze:** een CI-runner laat de stdout-stream zien, een auditor copy-paste't 'm in de evidence-bundle. Plain text wins.

### D4. CI: officiële Docker Hub images, rolling tag tot het breekt

**Keuze:** `almalinux:9`, `ubuntu:24.04`, `archlinux:latest`. Pinnen pas wanneer een upstream-wijziging CI breekt zonder dat er aan de repo iets veranderd is.

**Alternatieven:**
- *Vooraf pinnen op SHA*: maximaal reproduceerbaar, maar elke upstream-patch betekent een chore-PR; in praktijk roest de pin.
- *Alleen vendor-images vanuit een eigen registry*: complexer dan deze repo nodig heeft.

**Waarom deze:** officiële images zijn de community-standaard en worden door de vendor zelf onderhouden. Rolling tags zijn boring (`actions/checkout@v4` doet hetzelfde). Wanneer Arch breekt is dat een concreet signaal — pin pas dan, met een comment die aangeeft waarom en wanneer.

### D5. EUPL-1.2 als license, expliciet vastgelegd in `LICENSE`

**Keuze:** Volledige EUPL-1.2-tekst in `LICENSE` (al impliciet aanwezig via SPDX-headers per script).

**Alternatieven:**
- *MIT / Apache-2.0*: dominanter in dev-tooling, makkelijker te scannen door SBOM-tools.
- *Geen LICENSE-file, alleen SPDX-headers*: technisch geldig, maar GitHub toont dan "No license" wat externe gebruikers afschrikt.

**Waarom deze:** consistent met de bestaande SPDX-headers (`# SPDX-License-Identifier: EUPL-1.2`). EUPL is OSI-approved, breed gedragen in Europese publieke-sector projecten, en past bij de NLnet/digitale-soevereiniteit-context van de auteur. Een `LICENSE`-file plus de motivatie in een `## License`-sectie onderaan de README is wat externe lezers verwachten.

### D6. `--version` op user-facing CLIs, niet op interne library-scripts

**Keuze:** `bootstrap.sh`, `check.sh`, en elke `common/*.sh` die als CLI bedoeld is (`install-pm-cooldown.sh`, `install-shell-tools.sh`, `incident-token-revoke.sh`, `scan.sh`, `rkhunter-check.sh`, `update.sh`, `uninstall.sh`). Niet op `common/lib.sh` (geen entrypoint) of `common/check-shell-headers.sh` (developer-tool, geen end-user CLI).

**Alternatieven:**
- *Overal*: scope-creep; `lib.sh` is geen entrypoint.
- *Alleen op `bootstrap.sh`*: een gebruiker die direct een sub-script draait krijgt geen versie-handvat.

**Waarom deze:** GNU-CLI-conventie volgt deze lijn (elke `bin/`-achtige tool krijgt `--version`; libraries niet).

### D7. Single bundled change, geen splits

**Keuze:** Alle zeven clusters in één OpenSpec change (`v1-release-readiness`).

**Alternatieven:**
- *Zeven aparte changes*: technisch netter qua granulariteit, maar elke change zou triviaal klein zijn en C6 hangt sowieso van A+B+C af.

**Waarom deze:** consistent met de oorspronkelijke delta-beschrijving ("kleinere clusters samen"). Eén release, één coherent verhaal in de CHANGELOG. PRs kunnen alsnog per cluster gemerged worden — de spec hoeft daarvoor niet gesplitst.

## Risks / Trade-offs

- **Rolling-image breuk** — `archlinux:latest` kan CI breken zonder repo-wijziging (zie D4). Mitigatie: pin-policy in spec, follow-up issue om de pin op te ruimen.
- **`VERSION` raakt out-of-sync met git tag** — een release-PR kan `VERSION` updaten zonder dat de tag volgt (of andersom). Mitigatie: C6 stap 6.4-6.5 expliciet sequentieel; eventueel later een lightweight pre-commit-check toevoegen, maar buiten v1.0.0-scope.
- **`WS_DRY_RUN` leaks** — als een gebruiker `export WS_DRY_RUN=1` in zijn shell zet en het vergeet, draait elke installer dry-run zonder dat hij het ziet. Mitigatie: elke installer print bij dry-run een duidelijke banner (`(dry-run; no changes made)`) — onmogelijk te missen.
- **EUPL-1.2 SBOM-coverage** — sommige SBOM-tools herkennen EUPL niet zo soepel als MIT/Apache. Geaccepteerd risico; SPDX-identifier maakt het machine-leesbaar genoeg.
- **`--version` early-exit conflicteert nooit met andere flags** — geforceerd in de spec (D6, scenario "vóór andere flags"). Geen risico op verrassend gedrag.
