---
status: draft
last_reviewed: 2026-07-13
---

# Supply-chain cooldown (npm / pnpm / bun / uv / pip)

A 7-day quarantine on fresh package versions, for both the Node and Python
ecosystems. Standalone reading — you don't need to know the rest of the
workstation-security baseline to judge the value of this.

## Why

The pattern is by now well known, in both ecosystems:

1. Attacker compromises a maintainer account (phishing, token leak, social
   engineering).
2. Attacker publishes a new patch version with malicious code (typically: a
   post-install / install-hook script that exfiltrates secrets).
3. Lockfiles with `^x.y.z` / `~x.y.z` constraints, or `pyproject.toml` with
   `>=x.y.z`, pick up the version automatically during the next `npm install` /
   `pnpm install` / `bun install` / `pip install` / `uv sync`.
4. Within 24-48h (npm) or a few hours (PyPI) the registry detects the version,
   takes it offline or quarantines it, and publishes an advisory.
5. Everyone who installed the version in step 3 is hit; everyone who installs
   after step 4 is not.

Recent incidents that a 7-day cooldown would have blocked:

- **npm — 2026-05-11** — a wave of malicious patch versions of popular
  packages, uploaded by compromised maintainer accounts.
- **PyPI — LiteLLM, March 2026** — live for 2 hours 32 minutes, well over
  119,000 downloads before PyPI quarantined it. A 3-day cooldown would have
  been enough.
- **PyPI — Telnyx, April 2026** — similar pattern, similar speed of detection
  and quarantine.

A 7-day cooldown categorically places you in group 2 (after step 4). No package
version reaches your lockfile before it is seven days old, so malicious versions
have time to be detected and yanked before they hit your build. It costs you
currency (you run seven days behind on patches) in exchange for drastically
lower supply-chain risk — a trade-off that for most workstation and dev
workflows is well worth it.

## Mechanism per package manager

Five tools, five configuration keys — all with the same semantics (refuse to
install if the published version is younger than the threshold):

| Manager | File                       | Key                              | Unit              | Minimum version |
|---------|----------------------------|----------------------------------|-------------------|-----------------|
| npm     | `~/.npmrc`                 | `min-release-age`                | days              | npm 11.10+      |
| pnpm    | `~/.npmrc`                 | `minimum-release-age`            | minutes           | pnpm 10.16+     |
| bun     | `~/.bunfig.toml`           | `[install] minimumReleaseAge`    | seconds           | bun 1.3+        |
| uv      | `~/.config/uv/uv.toml`     | `exclude-newer`                  | duration ("N days") | uv 0.9.17+    |
| pip     | `~/.config/pip/pip.conf`   | `[install] uploaded-prior-to`    | ISO 8601 (`PND`)  | pip 26.1+       |

`common/install-pm-cooldown.sh` writes all five at once, idempotently. Existing
content (auth tokens, custom registries, other keys, other TOML tables) is
preserved. File mode stays the existing mode, and becomes `0600` for new files
— auth tokens should never be world-readable.

```bash
bash common/install-pm-cooldown.sh             # default 7 days
bash common/install-pm-cooldown.sh --days 14   # other threshold
bash common/install-pm-cooldown.sh --check     # show current state only
bash common/install-pm-cooldown.sh --dry-run   # show what it would do, no changes
```

On systems where neither Node NOR Python is installed, the installer still
writes the corresponding config files: the cooldown only activates when you
later run the package-manager binary, so setting the config in advance costs
nothing.

## Three levels of scope: workstation, project, CI

`~/.npmrc`, `~/.bunfig.toml`, `~/.config/uv/uv.toml`, and
`~/.config/pip/pip.conf` are user-level. Good for your own interactive use on
your dev machine, but it leaves a gap:

| Scope          | Who reads user-level config? | Effect on cooldown |
|----------------|------------------------------|--------------------|
| Your workstation, you logged in | yes | active |
| Your workstation, another user on the same machine | no | not active |
| Docker build running as the `node` / `python` user | no | not active |
| CI runner (GitHub Actions, GitLab CI, etc.) | no | not active |

The CI runner is exactly where the attacker wants to land — that's where your
production build runs. So user-level alone is not enough.

**Per-project solution.** Drop config files in every repo you own:

```bash
# Node ecosystem — files are auto-detected by npm/pnpm/bun
cp common/templates/project-npmrc.example         <your-repo>/.npmrc
cp common/templates/project-bunfig.toml.example   <your-repo>/bunfig.toml

# Python ecosystem — uv auto-detects pyproject.toml; pip needs an env-var hop
$EDITOR <your-repo>/pyproject.toml   # merge in the [tool.uv] block from
                                     # common/templates/pyproject-uv-snippet.toml.example
cp common/templates/project-pip.conf.example      <your-repo>/pip.conf

git add .npmrc bunfig.toml pyproject.toml pip.conf
git commit -m "add: package-manager cooldown config"
```

None of the files contain secrets and all belong in version control. A CI
runner that checks out your project reads npm/pnpm/bun/uv automatically. **pip
is the exception**: pip does not read a project-local `pip.conf` without help —
you must set `PIP_CONFIG_FILE=$PWD/pip.conf` in CI, or configure the cooldown
via an env var (see below).

**CI-only solution.** For projects where you can't commit a file (shared with
teams that don't share this opinion), set the cooldown in CI environment
variables:

```yaml
# GitHub Actions:
env:
  # Node ecosystem (both npm and pnpm honor NPM_CONFIG_*)
  NPM_CONFIG_MIN_RELEASE_AGE: 7
  NPM_CONFIG_MINIMUM_RELEASE_AGE: 10080   # 7 * 24 * 60 minutes

  # Python ecosystem
  UV_EXCLUDE_NEWER: "7 days"              # uv 0.9.17+
  PIP_UPLOADED_PRIOR_TO: P7D              # pip 26.1+
```

No file change, no PR discussion, just a config block on the jobs that run `npm
install` / `pip install` / `uv sync`. bun has (as of 1.3) no equivalent env var
— for bun projects `bunfig.toml` is the only way. See
`common/templates/README.md` for the full table of variants.

## Override for urgent CVEs within the window

What if a real security patch drops within your 7-day window? For example:
`lodash` or `pydantic` has a CVE, the fix was published yesterday, your cooldown
blocks it. Two options:

**Per-install override** — only for the duration of one install command:

```bash
# Node
NPM_CONFIG_MIN_RELEASE_AGE=0 npm install lodash@4.17.45

# Python
pip install --uploaded-prior-to 2026-06-01T00:00:00Z pydantic==2.11.1
uv add --exclude-newer 'never' pydantic==2.11.1
```

**Per-project override** — if the project wants to adopt this CVE fix
permanently until the version is old enough anyway. Set the cooldown to 0 (or a
date before the fix) in the project-local config, commit that as a hotfix, and
revert when the cooldown would have let the package in anyway. Audit trail: the
commit itself is your proof that the override was deliberate.

Both overrides are opt-in. The default remains that an unread `npm install` or
`pip install` respects your cooldown.

## What this does NOT cover

- **Direct attacks via your IDE / editor extensions** — VSCode extensions,
  JetBrains plugins, and Sublime packages have their own update mechanisms.
  This cooldown doesn't work for them.
- **Browser extensions, OS packages, Docker base images** — other ecosystems,
  other mitigations. Pin Docker images to SHA if you're worried about them.
- **Compromised registry itself** — the cooldown relies on a working
  yank/quarantine mechanism. An attacker with registry control could in theory
  "un-yank" yanked versions.
- **Already-existing malicious versions > N days old** — anything that has been
  circulating for more than 7 days falls outside the quarantine. The cooldown
  is a time filter, not an integrity check.
- **Tools without a cooldown feature** — `poetry` and `pipenv` (Python) have no
  native equivalent as of 2026-05; for those tools the mitigation is indirect
  (via pin files or a wrapper).

For the threat model this tool does and does not defend against: see
[`threat-model.md`](threat-model.md).

## See also

- `common/install-pm-cooldown.sh` — installer script (npm/pnpm/bun/uv/pip).
- `common/templates/project-npmrc.example`,
  `common/templates/project-bunfig.toml.example`,
  `common/templates/pyproject-uv-snippet.toml.example`,
  `common/templates/project-pip.conf.example` — per-project templates.
- `common/templates/README.md` — overview of which template when, plus the CI
  env-var table.
- Motivating incidents: npm supply-chain wave of 2026-05-11; PyPI LiteLLM
  incident (March 2026) and Telnyx incident (April 2026).
- External primary sources: [PyPI security blog](https://blog.pypi.org/),
  [uv exclude-newer docs](https://docs.astral.sh/uv/reference/settings/),
  [pip --uploaded-prior-to](https://pip.pypa.io/en/stable/cli/pip_install/),
  [cooldowns.dev](https://cooldowns.dev/).
