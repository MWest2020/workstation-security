---
status: current
last_reviewed: 2026-07-13
---

# workstation-security documentation

**workstation-security** is a best-effort security baseline for Linux
developer workstations (Alma / Arch / Ubuntu, and WSL2): daily malware and
rootkit scans, a supply-chain package cooldown, an incident-response runbook,
and a read-only audit tool — installed from a fresh clone and mapped to
compliance frameworks. Start with the repository [`README.md`](../README.md)
for installation and usage; the pages here go one level deeper.

**Status:** the pages below were migrated to this structure without content
review (`status: draft`); the mappings and reasoning are a first pass. Only a
real review promotes a page to `status: current`.

## Sections

### Reference

- [reference/compliance.md](reference/compliance.md) — mapping of components to
  control IDs in ISO 27001:2022, SOC 2, NEN 7510-2:2017, and BIO, plus an
  explicit gap list.

### Explanation

- [explanation/threat-model.md](explanation/threat-model.md) — what we do and
  do not defend against, with the operating assumptions.
- [explanation/strategy.md](explanation/strategy.md) — the install strategy:
  required vs optional components, failure modes, and partial-install recovery.
- [explanation/supply-chain-cooldown.md](explanation/supply-chain-cooldown.md)
  — the 7-day package-version quarantine for npm / pnpm / bun / uv / pip.
- Laag 4 (agent-guardrails) is verhuisd naar `ConductionNL/claude-plugins`, zie `docs/guardrail-lagen.md` daar
  — the secret deny-list for agent CLIs with filesystem access, and what that
  layer does not cover.
