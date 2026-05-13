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

Copy, rename, commit. The files contain only public settings — no secrets.

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
