---
status: draft
last_reviewed: 2026-07-13
---

# Threat model

What workstation-security defends against and what it does not, and why.
Intended to give implementation engineers and security reviewers an honest
picture in 15 minutes, so that expectations don't drift apart between "what we
installed" and "what that actually solves".

## Audience and operating assumptions

- **Workstation, not a server.** The assumption is a developer laptop or
  desktop with a single primary user who is largely root on their own machine.
  Server hardening (auditd baselines, SELinux mandatory policies, agent-based
  EDR) is out of scope.
- **The user is technically competent.** The user reads commit messages,
  understands `sudo`, knows what a GitHub PAT is. No childproof locks.
- **The workstation is connected to the internet and touches code.** No
  air-gapped enclave, no kiosk mode. It compiles, runs `npm install`, uses
  `gh`. The threat model is built around that.
- **Compliance is a motivation, not an end goal.** The controls exist because
  ISO 27001 / SOC 2 / NEN 7510 / BIO require them — not because they prevent
  the most likely attack. Important: a dev machine with ClamAV is not safer on
  the commodity-malware front (Linux malware is rare), but it is demonstrably
  in scope.

## In scope — what we do defend

### Commodity Linux malware

**What:** Classic viruses, trojans, ransomware payloads that land on a Linux
dev machine via download or email attachment.

**Defense:**
- `clamscan` daily on `/home` (`scan.sh` via systemd timer).
- ClamAV daemon (`clamd@scan` or `clamav-daemon`) for realtime capabilities.
- `wall` notification on findings (visible only to logged-in sessions — see
  gaps).

**Honestly:** Linux malware on a dev machine is low probability. The primary
reason to run this is **demonstrability for audit** (A.8.7 / CC6.8 / NEN 7510
12.2 / BIO U.07.03), not "stopping Conficker".

### Rootkits on the Linux host

**What:** Persistence tooling that hides beneath the OS (LD_PRELOAD hooks,
kernel modules, modified system binaries).

**Defense:**
- `rkhunter --check` daily (`rkhunter-check.sh` via systemd timer).
- `wall` notification on warnings.

**Honestly:** rkhunter is signature-based and misses modern rootkits. For
serious rootkit detection you need an EDR or YARA-based tooling. This is the
minimum an auditor expects to see under "rootkit detection".

**Not on WSL** — there the false positives are so high that alarm fatigue
undermines the whole control (see `README.md` → WSL Support).

### Supply-chain attacks via npm / pnpm / bun

**What:** An attacker publishes a malicious version of a legitimate package
(event-stream, ua-parser-js, node-ipc patterns) or a typosquat. That version
gets installed on a dev machine and runs postinstall scripts.

**Defense:**
- 7-day cooldown (`install-pm-cooldown.sh`) — refuses package versions younger
  than N days. npm usually yanks malicious uploads within 24-48 hours; a 7-day
  window catches them before they land in lockfiles.
- `~/.claude/CLAUDE.md` rule: `npm ci --ignore-scripts` is the baseline,
  postinstall enabled explicitly per package.
- Pre-commit `gitleaks` hook (via `install-shell-tools.sh`) — catches secrets
  that would accidentally be committed into `node_modules/` paths.

**Honestly:** a patient attacker can wait out the cooldown. It is **defense in
depth**, not absolution. Against a targeted attack on a specific organization
it barely helps.

### Stolen GitHub PAT with dead-man's switch

**What:** An attacker compromises a gh-PAT and installs a service that
periodically polls `api.github.com/user`. When the user tries to revoke the
token (HTTP 40x), the service triggers `rm -rf ~/` (CanisterSprawl-class
attack, carlini analysis 2026-05-12).

**Defense:**
- `incident-token-revoke.sh` — capture-first (sha256 + last4 for verify),
  detect IOCs + heuristics, **SIGKILL before systemctl stop** (otherwise a
  TERM trap catches the signal and still triggers `rm -rf`), evidence outside
  `$HOME` (in `/tmp/incident-<ts>/` so it survives the delete window), manual
  revoke + verify.
- On WSL: scope warning at start that Windows-host persistence (Task Scheduler,
  HKCU Run keys, startup folder) is outside this script.

**Honestly:** this is a **specific attack class**, not a general IR flow. Other
token compromises (AWS IAM keys, Slack bot tokens) are not covered here — they
need their own runbook.

### Audit trail of what is configured on the system

**What:** An auditor asks "what runs on this workstation, when was it changed,
and what does it do".

**Defense:**
- `CHANGELOG.md` with dated entries per change.
- `check.sh` as a read-only audit tool with a deterministic exit code.
- `# role:` marker on every script — `grep -rn '^# role:' scripts/` gives the
  complete process-boundaries map in a single scan.
- Logrotate on `/var/log/clamav/` and `/var/log/rkhunter.log` (28 days
  retained).

## Out of scope — what we explicitly do NOT defend

### Nation-state / APT actors

Kernel-level implants, custom in-memory droppers, zero-day exploits.
Workstation-security is a baseline; against an actor with budget and patience
no off-the-shelf solution works without EDR and proactive threat hunting.
Acknowledge it in your risk register; workstation-security does not cover it.

### Remote Access Trojans (RAT) after initial compromise

Once an attacker has `bash` on the machine (via phishing, browser exploit,
supply chain), they can either disable the defenses (root) or bypass them
(user-level persistence in `~/.local/bin` that rkhunter misses). The IR script
catches one specific variant (gh-token-monitor); generic RAT detection is out
of scope.

### Adversary-in-the-middle (AitM) on the network

A hostile Wi-Fi network, compromised proxy, or route injection. TLS
verification and VPN choice are separate controls that must live elsewhere
(`/etc/ssh/ssh_config`, browser TLS settings, organizational VPN policy).
Workstation-security does not interfere there.

### Social engineering

Phishing, pretexting, vishing. Attacks on people. No script helps here — only
training and policy.

### Physical attacks

An attacker with physical access (stolen laptop, evil-maid attack, USB drop
with malicious firmware). Disk encryption is the relevant control here
(BitLocker/LUKS), but workstation-security **does not install disk
encryption** — only checking for it is on the follow-up roadmap. For laptops
in production: use LUKS or BitLocker, independent of this script.

### Web browser attacks

A hostile website exploiting JS-engine bugs, or browser extensions that steal
credentials. Here browser hardening (HSTS preload, extension policy via group
policy or an MDM), uBlock Origin, and a good password manager are the relevant
controls.

### Server-side attacks

An attacker trying to SSH into this machine. SSH hardening (key-only auth,
fail2ban, port changes) is a separate control. Workstation-security assumes the
machine exposes no inbound services that are publicly reachable — a dev laptop,
not a server.

## Operating assumptions

The threat model depends on these assumptions; if one of them does not hold for
your deployment, revisit which "out of scope" items actually remain out of
scope.

| Assumption | What if it doesn't hold? |
|---|---|
| Single primary user with root | Multi-user dev-shared machine: rkhunter warnings can overwrite each other; reconsider permissions on `/var/log/clamav/` |
| Internet connectivity available | Air-gapped: cooldown and signature updates stall; an offline update flow is required |
| The user installs no fresh packages within 7 days | Urgent CVE fix needed: per-project `.npmrc` with `min-release-age=0`, documented in CHANGELOG |
| systemd is the init (or WSL2 with opt-in) | OpenRC, init.d, runit: timers don't work; manual cron installation for scans needed |
| `/home` is on a non-network filesystem | NFS-mounted home: ClamAV scan can take hours; adjust `scan.sh` exclude patterns |
| The wall notification reaches the user | Headless / cloud-IDE environment: findings disappear unseen; add mail reporting (see `incident-token-revoke.env.example` for the pattern) |

## Changes to this document

Update when:
- A new script or installer is added → possibly expand "in scope"
- An attack class that was previously out of scope comes into scope → document
  the reason + defense
- An operating assumption changes → revise the out-of-scope section
- A control is removed → explain why (moved to another tool, became redundant,
  etc.)
