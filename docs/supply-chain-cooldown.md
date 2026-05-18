# Supply-chain cooldown (npm / pnpm / bun / uv / pip)

Een 7-daagse quarantine op verse pakketversies, voor zowel Node- als Python-ecosystemen. Standalone te lezen — je hoeft de rest van de workstation-security baseline niet te kennen om hier de waarde van in te schatten.

## Waarom

Het patroon is inmiddels routineus, op beide ecosystemen:

1. Aanvaller compromitteert een maintainer-account (phishing, token-leak, social engineering).
2. Aanvaller publiceert een nieuwe patch-versie met malicious code (typisch: post-install / install-hook script dat secrets exfiltreert).
3. Lockfiles met `^x.y.z` / `~x.y.z` constraints, of `pyproject.toml` met `>=x.y.z`, pakken de versie automatisch op tijdens de volgende `npm install` / `pnpm install` / `bun install` / `pip install` / `uv sync`.
4. Binnen 24-48u (npm) of een paar uur (PyPI) detecteert de registry de versie, yankt of quarantaineert 'm, en publiceert een advisory.
5. Iedereen die in stap 3 de versie installeerde is geraakt; iedereen die na stap 4 installeert niet.

Recente incidenten die door een 7-daagse cooldown waren geblokkeerd:

- **npm — 2026-05-11** — golf van kwaadaardige patch-versies van populaire pakketten, geüpload door gecompromitteerde maintainer-accounts.
- **PyPI — LiteLLM, maart 2026** — 2 uur 32 minuten live, ruim 119.000 downloads voordat PyPI 'm quarantaineerde. Een 3-daagse cooldown was genoeg geweest.
- **PyPI — Telnyx, april 2026** — vergelijkbaar patroon, vergelijkbare snelheid van detectie en quarantine.

Een 7-daagse cooldown plaatst je categorisch in groep 2 (na stap 4). Geen pakketversie haalt je lockfile vóór 'ie zeven dagen oud is, dus malicious versies hebben tijd om gedetecteerd en geyankt te worden voordat ze jouw build raken. Het kost je actualiteit (je loopt zeven dagen achter op patches) in ruil voor een drastisch lager supply-chain-risico — een trade-off die voor de meeste workstation- en dev-workflows ruimschoots de moeite waard is.

## Mechanisme per package-manager

Vijf tools, vijf configuratiesleutels — allemaal met dezelfde semantiek (refuseren te installeren als de gepubliceerde versie jonger is dan de drempel):

| Manager | File                       | Key                              | Eenheid           | Minimum versie  |
|---------|----------------------------|----------------------------------|-------------------|-----------------|
| npm     | `~/.npmrc`                 | `min-release-age`                | dagen             | npm 11.10+      |
| pnpm    | `~/.npmrc`                 | `minimum-release-age`            | minuten           | pnpm 10.16+     |
| bun     | `~/.bunfig.toml`           | `[install] minimumReleaseAge`    | seconden          | bun 1.3+        |
| uv      | `~/.config/uv/uv.toml`     | `exclude-newer`                  | duration ("N days") | uv 0.9.17+    |
| pip     | `~/.config/pip/pip.conf`   | `[install] uploaded-prior-to`    | ISO 8601 (`PND`)  | pip 26.1+       |

`common/install-pm-cooldown.sh` schrijft alle vijf tegelijk, idempotent. Bestaande inhoud (auth tokens, custom registries, andere keys, andere TOML-tables) blijft staan. File-modus blijft de bestaande modus, en wordt `0600` voor nieuwe files — auth-tokens horen nooit world-readable.

```bash
bash common/install-pm-cooldown.sh             # default 7 dagen
bash common/install-pm-cooldown.sh --days 14   # andere drempel
bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen
bash common/install-pm-cooldown.sh --dry-run   # toon wat het zou doen, geen wijzigingen
```

Op systemen waar geen Node OF geen Python geïnstalleerd is, schrijft de installer alsnog de bijbehorende config-files: de cooldown wordt pas geactiveerd wanneer je later het pakketmanager-binary draait, dus de config alvast zetten kost niks.

## Drie niveaus van scope: workstation, project, CI

`~/.npmrc`, `~/.bunfig.toml`, `~/.config/uv/uv.toml` en `~/.config/pip/pip.conf` zijn user-level. Goed voor je eigen interactieve gebruik op je dev-machine, maar levert een gat op:

| Scope          | Wie leest user-level config? | Effect op cooldown |
|----------------|------------------------------|--------------------|
| Jouw workstation, jij ingelogd | ja | actief |
| Jouw workstation, andere user op dezelfde machine | nee | niet actief |
| Docker build die als `node` / `python` user draait | nee | niet actief |
| CI-runner (GitHub Actions, GitLab CI, etc.) | nee | niet actief |

De CI-runner is precies waar de aanvaller wil belanden — daar draait je productiebuild. Dus user-level alleen is niet voldoende.

**Per-project oplossing.** Drop config-files in elke repo die je owned:

```bash
# Node ecosysteem — files worden auto-detect'd door npm/pnpm/bun
cp common/templates/project-npmrc.example         <jouw-repo>/.npmrc
cp common/templates/project-bunfig.toml.example   <jouw-repo>/bunfig.toml

# Python ecosysteem — uv auto-detect't pyproject.toml; pip vereist een env-var-hop
$EDITOR <jouw-repo>/pyproject.toml   # merge het [tool.uv]-blok uit
                                     # common/templates/pyproject-uv-snippet.toml.example
cp common/templates/project-pip.conf.example      <jouw-repo>/pip.conf

git add .npmrc bunfig.toml pyproject.toml pip.conf
git commit -m "add: package-manager cooldown config"
```

Geen van de files bevat secrets en alle horen in version control. Een CI-runner die je project checkt-out leest npm/pnpm/bun/uv automatisch. **pip is de uitzondering**: pip leest géén project-lokale `pip.conf` zonder hulp — je moet `PIP_CONFIG_FILE=$PWD/pip.conf` zetten in CI, of de cooldown via env-var (zie hieronder) configureren.

**CI-only oplossing.** Voor projecten waar je geen file mag committen (gedeeld met teams die deze opinie niet delen), zet de cooldown in CI environment variables:

```yaml
# GitHub Actions:
env:
  # Node ecosysteem (npm én pnpm honoreren NPM_CONFIG_*)
  NPM_CONFIG_MIN_RELEASE_AGE: 7
  NPM_CONFIG_MINIMUM_RELEASE_AGE: 10080   # 7 * 24 * 60 minuten

  # Python ecosysteem
  UV_EXCLUDE_NEWER: "7 days"              # uv 0.9.17+
  PIP_UPLOADED_PRIOR_TO: P7D              # pip 26.1+
```

Geen file-wijziging, geen PR-discussie, alleen een config-blok bij de jobs die `npm install` / `pip install` / `uv sync` draaien. bun heeft (vanaf 1.3) géén equivalent env-var — voor bun-projects is `bunfig.toml` de enige weg. Zie `common/templates/README.md` voor de volledige tabel met varianten.

## Override voor urgente CVEs binnen het venster

Wat als er een echte security-patch valt binnen je 7-daagse venster? Bijvoorbeeld: `lodash` of `pydantic` heeft een CVE, de fix is gisteren gepubliceerd, je cooldown blokkeert 'm. Twee opties:

**Per-install override** — alleen voor de duur van één install-commando:

```bash
# Node
NPM_CONFIG_MIN_RELEASE_AGE=0 npm install lodash@4.17.45

# Python
pip install --uploaded-prior-to 2026-06-01T00:00:00Z pydantic==2.11.1
uv add --exclude-newer 'never' pydantic==2.11.1
```

**Per-project override** — als het project deze CVE-fix permanent wil opnemen tot de versie sowieso oud genoeg is. Zet in de project-lokale config de cooldown op 0 (of een datum vóór de fix), commit dat als hotfix, en revert wanneer de cooldown het pakket toch zou hebben binnengelaten. Audit-trail: de commit zelf is je bewijs dat de override bewust is gedaan.

Beide overrides zijn opt-in. De default blijft dat een ongelezen `npm install` of `pip install` jouw cooldown respecteert.

## Wat dekt dit NIET af

- **Direct attacks via je IDE / editor extensions** — VSCode-extensies, JetBrains-plugins en Sublime-packages hebben hun eigen update-mechanismen. Daar werkt deze cooldown niet voor.
- **Browser-extensies, OS-packages, Docker base-images** — andere ecosystems, andere mitigations. Pin Docker images op SHA als je daar zorgen over hebt.
- **Compromised registry zelf** — de cooldown vertrouwt op een functionerend yank/quarantine-mechanisme. Een aanvaller met registry-control kan in theorie geyankte versies "ondoenken".
- **Pre-existing malicious versies > N dagen oud** — wat al meer dan 7 dagen circuleert valt buiten de quarantine. De cooldown is een tijds-filter, geen integriteits-check.
- **Tools zónder cooldown-feature** — `poetry` en `pipenv` (Python) hebben geen native equivalent als van 2026-05; voor die tools is de mitigatie indirect (via pin-files of een wrapper).

Voor het bedreigingsmodel waar deze tool wel/niet voor verdedigt: zie [`threat-model.md`](threat-model.md).

## Zie ook

- `common/install-pm-cooldown.sh` — installer-script (npm/pnpm/bun/uv/pip).
- `common/templates/project-npmrc.example`, `common/templates/project-bunfig.toml.example`, `common/templates/pyproject-uv-snippet.toml.example`, `common/templates/project-pip.conf.example` — per-project templates.
- `common/templates/README.md` — overzicht van wanneer welke template, plus CI env-var-tabel.
- Aanleidingen: npm supply-chain golf van 2026-05-11; PyPI LiteLLM-incident (maart 2026) en Telnyx-incident (april 2026).
- Externe primaire bronnen: [PyPI security blog](https://blog.pypi.org/), [uv exclude-newer docs](https://docs.astral.sh/uv/reference/settings/), [pip --uploaded-prior-to](https://pip.pypa.io/en/stable/cli/pip_install/), [cooldowns.dev](https://cooldowns.dev/).
