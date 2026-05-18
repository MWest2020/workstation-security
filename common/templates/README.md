# Project templates

Drop-in config snippets for **per-project** supply-chain hardening. These
extend the user-level cooldown (`~/.npmrc`, `~/.bunfig.toml`) into places it
otherwise can't reach: CI/CD runners, fresh clones on new machines, contractor
laptops, and anything that doesn't share your home directory.

## When to use

- Every Node/Bun project you own or maintain.
- Especially anything that runs `npm ci` / `pnpm install` / `bun install` in CI.

## What to drop in

| Source | Destination | When |
|---|---|---|
| `project-npmrc.example` | `<repo>/.npmrc` | Any npm or pnpm project |
| `project-bunfig.toml.example` | `<repo>/bunfig.toml` | Any bun project |
| `pre-commit-config-shell.yaml.example` | `<repo>/.pre-commit-config.yaml` | Any repo with shell scripts |
| `bash-script-template.sh` | `<repo>/scripts/<new>.sh` (as starting point) | Any new shell script |

Copy, rename, commit. The files contain only public settings — no secrets.

### Shell-script conventions

`bash-script-template.sh` codifies the convention checked by
`common/check-shell-headers.sh` (used by `pre-commit-config-shell.yaml.example`):

- `#!/usr/bin/env bash` shebang (cross-platform — Apple's `/bin/bash` is 3.2)
- `# SPDX-License-Identifier:` in first 5 lines
- `# role: <entrypoint|library|container-entrypoint|installer|tool>` marker
- `set -euo pipefail` for `role=entrypoint` and `role=installer`
- A `# Usage:` block with concrete invocations (incl. crontab/Docker CMD where applicable)

Run `bash common/check-shell-headers.sh --all <dir>` to audit existing scripts
without modifying them.

### Pre-commit gates

`pre-commit-config-shell.yaml.example` wires up: ShellCheck, shfmt --check,
gitleaks, jscpd (duplication), and the header-convention check. All hooks are
**gates, not auto-fixers** — fix locally and re-stage, don't let the hook
silently rewrite. Install the tools first:

```bash
bash common/install-shell-tools.sh
```

## Verifying before commit

```bash
# No auth tokens or secrets leaked in:
grep -E '(_authToken|password|secret|token)' .npmrc bunfig.toml 2>/dev/null
```

If any output appears: stop, move the secret to an env var, and re-stage.

## CI alternative

If you can't commit a project-level file (e.g. the repo is shared with teams
that don't want this opinion), set these env vars in your CI provider instead:

```
NPM_CONFIG_MIN_RELEASE_AGE=7
NPM_CONFIG_MINIMUM_RELEASE_AGE=10080
```

Both npm and pnpm honor the `NPM_CONFIG_*` form.

## Override (rarely justified)

Per-install override for an urgent CVE-fix where the patched version is
younger than the cooldown window:

```bash
npm ci --min-release-age=0      # one-off; do NOT commit this to a script
```

Document the override in `CHANGELOG.md` with the CVE link and date.
