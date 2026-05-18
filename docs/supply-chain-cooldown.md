# Supply-chain cooldown (npm / pnpm / bun)

Een 7-daagse quarantine op verse pakketversies. Standalone te lezen — je hoeft de rest van de workstation-security baseline niet te kennen om hier de waarde van in te schatten.

## Waarom

Op 2026-05-11 kwam er weer een nieuwe golf supply-chain-attacks via het npm-ecosysteem: kwaadaardige patch-versies van populaire pakketten, geüpload door gecompromitteerde maintainer-accounts. Het patroon is inmiddels routineus:

1. Aanvaller compromitteert een maintainer-account (phishing, token-leak, social engineering).
2. Aanvaller publiceert een nieuwe patch-versie met malicious code (typisch: post-install script dat secrets exfiltreert).
3. Lockfiles met `^x.y.z` of `~x.y.z` constraints pakken de versie automatisch op tijdens de volgende `npm install` / `pnpm install` / `bun install`.
4. Binnen 24-48u detecteert npm de malicious versie, yankt 'm uit het register, en publiceert een advisory.
5. Iedereen die in stap 3 de versie installeerde is geraakt; iedereen die na stap 4 installeert niet.

Een 7-daagse cooldown plaatst je categorisch in groep 2 (na stap 4). Geen pakketversie haalt je lockfile vóór 'ie zeven dagen oud is, dus malicious versies hebben tijd om gedetecteerd en geyankt te worden voordat ze jouw build raken. Het kost je actualiteit (je loopt zeven dagen achter op patches) in ruil voor een drastisch lager supply-chain-risico — een trade-off die voor de meeste workstation- en dev-workflows ruimschoots de moeite waard is.

## Mechanisme per package-manager

Drie tools, drie configuratiesleutels — wel allemaal met dezelfde semantiek (refuseren te installeren als de gepubliceerde versie jonger is dan de drempel):

| Manager | File           | Key                            | Eenheid  | Minimum versie  |
|---------|----------------|--------------------------------|----------|-----------------|
| npm     | `~/.npmrc`     | `min-release-age`              | dagen    | npm 11.10+      |
| pnpm    | `~/.npmrc`     | `minimum-release-age`          | minuten  | pnpm 10.16+     |
| bun     | `~/.bunfig.toml` | `[install] minimumReleaseAge` | seconden | bun 1.3+        |

`common/install-pm-cooldown.sh` schrijft alle drie tegelijk, idempotent. Bestaande inhoud (auth tokens, custom registries, andere keys) blijft staan. File-modus blijft 0600 als de file al bestond, en wordt 0600 voor nieuwe files — auth-tokens horen nooit world-readable.

```bash
bash common/install-pm-cooldown.sh             # default 7 dagen
bash common/install-pm-cooldown.sh --days 14   # andere drempel
bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen
bash common/install-pm-cooldown.sh --dry-run   # toon wat het zou doen, geen wijzigingen
```

## Drie niveaus van scope: workstation, project, CI

`~/.npmrc` en `~/.bunfig.toml` zijn user-level. Dat is goed voor je eigen interactieve gebruik op je dev-machine, maar levert een gat op:

| Scope          | Wie leest user-level config? | Effect op cooldown |
|----------------|------------------------------|--------------------|
| Jouw workstation, jij ingelogd | ja | actief |
| Jouw workstation, andere user op dezelfde machine | nee | niet actief |
| Docker build die als `node`-user draait | nee | niet actief |
| CI-runner (GitHub Actions, GitLab CI, etc.) | nee | niet actief |

De CI-runner is precies waar de aanvaller wil belanden — daar draait je productiebuild. Dus user-level alleen is niet voldoende.

**Per-project oplossing.** Drop een `.npmrc` en `bunfig.toml` in elke Node/Bun repo die je owned:

```bash
cp common/templates/project-npmrc.example      <jouw-repo>/.npmrc
cp common/templates/project-bunfig.toml.example  <jouw-repo>/bunfig.toml
git add .npmrc bunfig.toml
git commit -m "add: package-manager cooldown config"
```

Beide files bevatten geen secrets en horen in version control. Een CI-runner die je project checkt-out leest ze automatisch.

**CI-only oplossing.** Voor projecten waar je geen file mag committen (gedeeld met teams die deze opinie niet delen), zet de cooldown in CI environment variables:

```yaml
# GitHub Actions:
env:
  NPM_CONFIG_MIN_RELEASE_AGE: 7
  NPM_CONFIG_MINIMUM_RELEASE_AGE: 10080   # 7 * 24 * 60 minuten
```

Geen file-wijziging, geen PR-discussie, alleen een config-blok bij de jobs die `npm install` draaien. Zie `common/templates/README.md` voor de volledige tabel met varianten.

## Override voor urgente CVEs binnen het venster

Wat als er een echte security-patch valt binnen je 7-daagse venster? Bijvoorbeeld: `lodash` heeft een CVE, de fix is in `4.17.45` (gisteren gepubliceerd), je cooldown blokkeert 'm. Twee opties:

**Per-install override** — alleen voor de duur van één install-commando. Bij npm en pnpm via een environment variable; bij bun via een lokale config-override:

```bash
# Tijdelijke override, alleen voor één install:
NPM_CONFIG_MIN_RELEASE_AGE=0 npm install lodash@4.17.45
```

**Per-project override** — als het project deze CVE-fix permanent op `0` wil zetten tot de versie wel oud genoeg is. Zet in de project-lokale `.npmrc` de waarde op `0`, commit dat als hotfix, en revert wanneer de cooldown het pakket toch zou hebben binnengelaten. Audit-trail: de commit zelf is je bewijs dat de override bewust is gedaan.

Beide overrides zijn opt-in. De default blijft dat een ongelezen `npm install` jouw cooldown respecteert.

## Wat dekt dit NIET af

- **Direct attacks via je IDE / editor extensions** — VSCode-extensies, JetBrains-plugins en Sublime-packages hebben hun eigen update-mechanismen. Daar werkt deze cooldown niet voor.
- **Browser extensies, OS-packages, Docker base-images** — andere ecosystems, andere mitigations. Pin Docker images op SHA als je daar zorgen over hebt.
- **Compromised npm-registry zelf** — de cooldown vertrouwt op een functionerend yank-mechanisme. Een aanvaller met registry-control kan in theorie geyankte versies "ondoenken".
- **Pre-existing malicious versies > N dagen oud** — wat al meer dan 7 dagen circuleert valt buiten de quarantine. De cooldown is een tijds-filter, geen integriteits-check.

Voor het bedreigingsmodel waar deze tool wel/niet voor verdedigt: zie [`threat-model.md`](threat-model.md).

## Zie ook

- `common/install-pm-cooldown.sh` — installer-script.
- `common/templates/project-npmrc.example`, `common/templates/project-bunfig.toml.example` — per-project templates.
- `common/templates/README.md` — overzicht van wanneer welke template, plus CI env-var-tabel.
- Aanleiding: het npm supply-chain incident van 2026-05-11 (zie ook eerdere incidenten in 2024 en 2025).
