# Habitat builder — apply-docs-contract

_run_id builder-apply-docs-contract-20260713-072543 · verdict ok · 2026-07-13T07:32:24Z_

---

Done. All implementation tasks complete and committed on the branch. Task 4.1 (open PR) requires a push + `gh`, which this environment doesn't have and which the habitat harness/Mark own — so I've stopped there as instructed, with the PR body prepared below.

## Run report — `apply-docs-contract`

**Branch:** `habitat/builder/apply-docs-contract` · **Commit:** `6444a53 docs: apply handbook docs contract`

### What I did
Restructured `docs/` to the handbook docs contract, migrated + **translated the existing pages to English** (the contract mandates one language per repo → English for this public repo), and added front matter everywhere.

New structure:
```
docs/
  index.md                              status: current   (new entry point)
  reference/compliance.md               status: draft     (← docs/compliance.md)
  explanation/threat-model.md           status: draft     (← docs/threat-model.md)
  explanation/strategy.md               status: draft     (← docs/strategy.md)
  explanation/supply-chain-cooldown.md  status: draft     (← docs/supply-chain-cooldown.md)
```
- Migrated pages: `status: draft` + `last_reviewed: 2026-07-13` (no content review performed — only a real review promotes to `current`).
- Deprecated redirect stubs left at all 5 old `docs/*.md` paths (`status: deprecated`) so links from `README.md` / `CONTRIBUTING.md` and any external links keep resolving. I did **not** edit `README.md`/`CONTRIBUTING.md` — out of scope; the stubs are what keep those links valid.
- `.mcp.json` was already in the root from the seed with the `TODO-change-3` placeholder — left untouched (task 2.4 already satisfied).
- Self-check passed: front matter on every page, no empty dirs, no Dutch left in the new content.

### Tasks
1.1 ✅ · 2.1 ✅ · 2.2 ✅ · 2.3 ✅ · 2.4 ✅ · 3.1 ✅ · **4.1 ⛔ blocked** (no `gh`, no upstream — harness pushes, Mark merges).

### For the PR (Mark to open)
Two points to surface in the PR body, one flagged per the proposal, one a judgment call:

1. **Deliberate contract deviation:** the self-check line "only permitted subfolders carry markdown" is bent by the 5 redirect stubs remaining in `docs/` root. They're kept intentionally to preserve inbound links (the migration explicitly asks to leave stubs) and marked `deprecated`. Delete them in a later change once you've confirmed no external links depend on them.
2. **Host-specific details:** none found. The docs reference only generic tool paths (`/var/log/clamav`, `~/.npmrc`, etc.), no real hostnames/IPs/credentials — nothing to relocate.

**Proposed PR:**
- Title: `docs: apply handbook docs contract`
- Body checklist: docs/ restructured to contract ✅ · existing docs migrated + stubs left ✅ · front matter (draft + last_reviewed) on migrated pages ✅ · index.md links README + sections ✅ · one language (English) ✅ · `.mcp.json` template with `TODO-change-3` placeholder ✅ · **note:** deprecated stubs remain in docs/ root by design; host-specific details: none found.

Stopping here — merge belongs to you.
