---
status: draft
last_reviewed: 2026-07-13
---

# Compliance mapping

Workstation-security components mapped onto specific controls in four
frameworks: ISO 27001:2022, SOC 2 (Trust Services Criteria 2017), NEN
7510-2:2017 (NL healthcare), and BIO (NL government).

## How to use

1. Identify the framework(s) in scope for your audit.
2. Look up each requested control in the mapping below.
3. Verify the evidence paths on the workstation itself — `check.sh` is the
   first stop for live-state evidence.
4. For controls this tool does **not** cover: see [Gaps](#gaps) — there you
   must either point to a compensating control or acknowledge the gap.

**Always verify against the literal control text of your framework edition.**
This mapping is verified against the main sections but not word for word;
control texts can shift between editions.

## Coverage summary

Workstation-security component → control IDs per framework:

| Component | ISO 27001:2022 | SOC 2 TSC | NEN 7510-2:2017 | BIO |
|---|---|---|---|---|
| ClamAV scan + daemon | A.8.7 | CC6.6, CC6.8, CC7.1 | 12.2.1 | U.07.03 |
| rkhunter rootkit check | A.8.7 | CC6.8, CC7.2 | 12.2.1 | U.07.03 |
| systemd timers (auto-execution) | A.8.16 | CC7.1 | 12.4.1 | U.16.01 |
| Package-manager cooldown | A.8.8, A.8.19 | CC6.8, CC9.1 | 12.6.1 | U.09.04 |
| `incident-token-revoke.sh` IR | A.5.24, A.5.26 | CC7.3, CC7.4 | 16.1.1, 16.1.5 | U.16.01 |
| Pre-commit gates (gitleaks etc) | A.8.28, A.8.8 | CC8.1 | 14.2.1 | U.14.01 |
| CHANGELOG + audit trail | A.8.15 | CC7.2 | 12.4.1, 18.2.3 | U.16.01 |
| `check.sh` health audit | A.8.16, A.8.34 | CC7.1, CC7.2 | 12.4.1 | U.18.01 |
| Logrotate (28-day retention) | A.8.15 | CC7.2 | 12.4.1 | U.16.01 |

---

## ISO 27001:2022 — Annex A controls

The 2022 revision consolidated 114 controls into 93 across four themes (A.5
Organizational, A.6 People, A.7 Physical, A.8 Technological).
Workstation-security touches mostly A.8.

### A.5 Organizational controls

| Control | Name | Implementation | Evidence |
|---|---|---|---|
| A.5.24 | Information security incident management planning and preparation | `common/incident-token-revoke.sh` — prepared IR runbook with a documented flow (capture → detect → SIGKILL → disarm → invalidate → revoke → verify) | Script + `incident-token-revoke.env.example` |
| A.5.26 | Response to information security incidents | Same — executes the IR steps, archives evidence to `/tmp/incident-<ts>/`, supports optional mail notification | Script output + `/tmp/incident-*` directories |

### A.8 Technological controls

| Control | Name | Implementation | Evidence |
|---|---|---|---|
| A.8.7 | Protection against malware | ClamAV (`scan.sh` daily via timer) + rkhunter (`rkhunter-check.sh` daily via timer). Daemon mode via `clamd@scan` / `clamav-daemon`. Obtained via the per-OS installer (alma/arch/ubuntu). | `systemctl status clamav-scan.timer rkhunter-check.timer` + `/var/log/clamav/daily-scan.log` + `/var/log/rkhunter.log` |
| A.8.8 | Management of technical vulnerabilities | (a) `common/update.sh` updates ClamAV signatures + rkhunter database daily via `av-update.timer`. (b) `install-pm-cooldown.sh` configures a 7-day package cooldown to keep malicious supply-chain uploads out of lockfiles. | `systemctl status av-update.timer` + `~/.npmrc` cooldown keys + signature timestamps via `check.sh` |
| A.8.15 | Logging | Per-component logging to `/var/log/clamav/*.log` and `/var/log/rkhunter.log`. Logrotate (`common/logrotate.conf`) rotates weekly, 4 weeks retained. CHANGELOG.md documents every change to the tool itself. | `ls -lah /var/log/clamav/` + `cat /etc/logrotate.d/workstation-security` + the repo's CHANGELOG.md |
| A.8.16 | Monitoring activities | `check.sh` as a read-only audit tool, exit code = number of problems (cron/CI usable). Verifies services, timers, signature age, and last-scan data. | `bash check.sh` output + exit code |
| A.8.19 | Installation of software on operational systems | npm/pnpm/bun cooldown via `install-pm-cooldown.sh` prevents installation of package versions younger than N days. Workstation level (`~/.npmrc`) plus per-project templates (`common/templates/project-*`) for CI. | `~/.npmrc`, `~/.bunfig.toml`, project-level `.npmrc` |
| A.8.28 | Secure coding | Pre-commit gates (`install-shell-tools.sh` + `templates/pre-commit-config-shell.yaml.example`): shellcheck, shfmt --check, gitleaks (secret scanning), jscpd (duplication), header-convention validator. Gates, not auto-fix — divergence between local and CI is prevented. | `.pre-commit-config.yaml` in every repo + `pre-commit run --all-files` output |
| A.8.34 | Protection of information systems during audit testing | `check.sh` is read-only; no changes to system state during audit runs. Dry-run mode for `incident-token-revoke.sh` (`--dry-run`). | Script comments + commit history for read-only proof |

**Partial / weak claims** (transparent about coverage):
- A.8.12 Data leakage prevention — only the token-leak scenario is covered by
  the IR script; general DLP is out of scope.
- A.8.27 Secure system architecture — pre-commit gates contribute indirectly,
  but workstation-security is not an architecture tool.

---

## SOC 2 — Trust Services Criteria (2017)

Workstation-security touches mostly the Common Criteria CC6 (Logical Access)
and CC7 (System Operations). CC8 (Change Management) is also touched
indirectly via the pre-commit gate philosophy.

### CC6 — Logical and Physical Access Controls

| Criterion | Abbreviated text | Implementation |
|---|---|---|
| CC6.6 | Implements logical access security ... including measures to ... mitigate the risks ... such as introduction of malicious software | ClamAV + rkhunter + cooldown — three layers against malware introduction (see A.8.7 / A.8.8 above). |
| CC6.8 | Implements controls to prevent or detect and act upon the introduction of unauthorized or malicious software | (a) ClamAV scan with wall notification on findings. (b) Pre-commit gitleaks catches secrets. (c) Cooldown catches malicious npm uploads. (d) IR script acts on detected token compromise. |

### CC7 — System Operations

| Criterion | Abbreviated text | Implementation |
|---|---|---|
| CC7.1 | Use procedures, ... and software tools ... to detect changes in the configuration ... that result from ... unauthorized actions | `check.sh` audit + rkhunter rootkit detection + ClamAV daemon. |
| CC7.2 | Monitors system components ... for anomalies indicative of malicious acts | Daily scan logs + `check.sh` as a monitoring probe (exit code for cron/CI alerting). Logrotate retains 28 days of history. |
| CC7.3 | Evaluates security events to determine whether they could or have resulted in a failure | `incident-token-revoke.sh` — a structured response path for one specific event class (CanisterSprawl). |
| CC7.4 | Responds to identified security incidents by executing a defined incident response program | Same; the IR script is literally an executed incident-response program with capture → detect → neutralize → verify. |

### CC8 — Change Management

| Criterion | Abbreviated text | Implementation |
|---|---|---|
| CC8.1 | Authorizes, designs, ... approves, and implements changes ... to ... infrastructure ... using a change management process | Pre-commit gate philosophy: hooks are gatekeepers, not auto-fixers. Every change goes through a git commit with a counted reviewer flow (CHANGELOG update mandatory). |

### CC9 — Risk Mitigation

| Criterion | Abbreviated text | Implementation |
|---|---|---|
| CC9.1 | Identifies, selects, and develops risk mitigation activities for risks arising from potential business disruptions | The supply-chain cooldown is a documented risk-mitigation choice against the npm supply-chain incident scenario (see threat-model.md). |

---

## NEN 7510-2:2017 — Information security controls for healthcare

NEN 7510-2 follows the ISO 27002:2013 numbering. The controls below are the
NEN-specific elaborations.

| Control | Name | Implementation |
|---|---|---|
| 12.2.1 | Controls against malware | ClamAV + rkhunter, daily via timers. (see A.8.7 ISO 27001 mapping for evidence paths) |
| 12.4.1 | Event logging | `/var/log/clamav/*` + `/var/log/rkhunter.log` + `check.sh` reporting + CHANGELOG. Logrotate 28 days. |
| 12.4.3 | Administrator and operator logs | The systemd journal captures timer-execution events; `journalctl --user -u av-update.timer` (per user-systemd installation). |
| 12.6.1 | Management of technical vulnerabilities | (a) `update.sh` for signatures. (b) `install-pm-cooldown.sh` for supply chain. (c) `update.sh` tries to fetch a missing `rkhunter` if it becomes available via the package manager. |
| 14.2.1 | Secure development policy | Pre-commit gates enforce a baseline quality: shellcheck, secret scanning (gitleaks), formatter check (shfmt --check), duplication detection (jscpd). |
| 16.1.1 | Responsibilities and procedures for information security incidents | `incident-token-revoke.sh` — a documented procedure for one specific incident class. |
| 16.1.5 | Response to information security incidents | Same — an executable incident-response script with capture, detect, neutralize, verify steps. |
| 18.2.3 | Technical compliance review | `check.sh` as an automated technical-compliance check; the output is auditable. |

**NEN 7510-specific notes:**
- 11.2.6 (Security of equipment and assets off-premises): particularly relevant
  for healthcare institutions on laptops in patient-care contexts —
  workstation-security does not cover this (would require disk encryption +
  remote wipe).
- 14.1.3 (Protecting transactions): not applicable to a workstation tool.

---

## BIO — Baseline Informatiebeveiliging Overheid

BIO follows ISO 27002 numbering with government-specific elaborations. Below
are the BIO controls that workstation-security covers; numbers with U. are the
elaborations, with B. the basic measures.

| Control | Name | Implementation |
|---|---|---|
| U.07.03 | Anti-malware software | ClamAV + rkhunter via systemd timers — automatic daily scans + signature updates. |
| U.09.04 | Patch management | (a) `update.sh` daily for AV signatures. (b) `install-pm-cooldown.sh` for package cooldown — prevents installation of too-fresh or malicious packages. |
| U.14.01 | Secure development | Pre-commit gates: shellcheck + shfmt + gitleaks + jscpd. The gate philosophy (no auto-fix) prevents silent divergence. |
| U.16.01 | Management of logs | Per-component logs + logrotate 28-day retention. Auditable via `check.sh`. |
| U.16.02 | Security incidents | `incident-token-revoke.sh` as a specific incident procedure. A more general IR policy must live elsewhere (organizational level, not a workstation tool). |
| U.18.01 | Compliance with legislation and regulations | `check.sh` as an automatable compliance check + CHANGELOG for audit traceability of changes to the tool. |

---

## Gaps

Controls that *typically* fall within an audit scope for a developer
workstation but that workstation-security **does not cover**:

| Gap | Frameworks | What workstation-security does/doesn't do |
|---|---|---|
| Disk encryption (LUKS / BitLocker) | ISO 27001 A.8.24, SOC 2 CC6.1, NEN 7510 18.1.3, BIO U.05.01 | NOT installed. Compensating: document that the organization mandates LUKS-at-OS-install or BitLocker via group policy. Roadmap item: optional read-only check in `check.sh` (reporting, no install). |
| Firewall state (firewalld/ufw) | ISO 27001 A.8.21, BIO U.06.01 | NOT checked. Compensating: the organizational baseline image ships firewalld/ufw active. Roadmap: `check.sh` addition for reporting. |
| Automatic OS security updates | ISO 27001 A.8.8, BIO U.09.04 | NOT configured. Distro level (dnf-automatic, unattended-upgrades) is expected; Arch is explicitly manual (rolling-release choice, document in policy). |
| Screen lock / clear desk | ISO 27001 A.7.7 | NOT checked. Desktop-environment specific (GNOME / KDE / etc); too user-specific for a baseline tool. Document in organizational policy. |
| Endpoint Detection & Response (EDR) | Not explicitly required by these frameworks, but often requested in practice | NOT installed. Workstation-security explicitly positions itself as a baseline, not an EDR replacement (see threat-model.md → "Out of scope"). |
| Centralized log aggregation | ISO 27001 A.8.15 for a multi-host context, not for a single workstation | NOT configured. The `wall` notification is local-only. Roadmap: optional SMTP mail in `scan.sh` / `rkhunter-check.sh` (same pattern as the IR script). |
| Multi-factor authentication (MFA) | ISO 27001 A.8.5, SOC 2 CC6.1 | Out of scope — MFA is a directory/IdP choice (Azure AD, Google Workspace), not a workstation tool. |
| DLP (general data-leak prevention) | ISO 27001 A.8.12 | Only the GitHub-PAT-leak scenario is covered by `incident-token-revoke.sh`. General DLP (USB blocking, clipboard monitoring) is out of scope. |

## Evidence-collection appendix

For an audit-evidence package: these paths + commands give the relevant state.

```bash
# System overview (read-only audit)
sudo bash check.sh

# Service / timer state (on systemd systems)
systemctl status clamav-scan.timer rkhunter-check.timer av-update.timer
systemctl list-timers --all

# Live logs (recent scans)
sudo ls -lah /var/log/clamav/
sudo tail -50 /var/log/clamav/daily-scan.log
sudo tail -50 /var/log/rkhunter.log

# Configured retention
cat /etc/logrotate.d/workstation-security

# Supply-chain cooldown state
bash common/install-pm-cooldown.sh --check

# Pre-commit gates present per repo
ls .pre-commit-config.yaml
pre-commit run --all-files  # → must be 5/5 green

# Change traceability
cat CHANGELOG.md   # in the workstation-security repo
git log --oneline  # shows all changes since initial install

# IR-tool dry run (no state change, detection output only)
bash common/incident-token-revoke.sh --dry-run
```

For controls that have no direct evidence path (organizational policy,
training, etc.): those belong in an organization-wide information-security
policy, not on an individual workstation.
