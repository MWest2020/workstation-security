# Compliance mapping

Workstation-security componenten gemapt op specifieke controls in vier
frameworks: ISO 27001:2022, SOC 2 (Trust Services Criteria 2017),
NEN 7510-2:2017 (NL healthcare), en BIO (NL overheid).

## Hoe te gebruiken

1. Identificeer de framework(s) in scope voor jouw audit.
2. Zoek per gevraagde control in de mapping hieronder.
3. Verifieer de evidence-paden op het werkstation zelf — `check.sh` is
   de eerste stop voor live-state-bewijs.
4. Voor controls die deze tool **niet** dekt: zie [Gaps](#gaps) — daar
   moet je óf een compensating control aanwijzen óf de gap erkennen.

**Verifieer altijd tegen de letterlijke control-tekst van jouw
framework-uitgave.** Deze mapping is geverifieerd tegen de hoofdsecties
maar niet woord-voor-woord; control-teksten kunnen tussen edities
verschuiven.

## Coverage summary

Workstation-security component → control-IDs per framework:

| Component | ISO 27001:2022 | SOC 2 TSC | NEN 7510-2:2017 | BIO |
|---|---|---|---|---|
| ClamAV scan + daemon | A.8.7 | CC6.6, CC6.8, CC7.1 | 12.2.1 | U.07.03 |
| rkhunter rootkit check | A.8.7 | CC6.8, CC7.2 | 12.2.1 | U.07.03 |
| systemd timers (auto-execution) | A.8.16 | CC7.1 | 12.4.1 | U.16.01 |
| Package-manager cooldown | A.8.8, A.8.19 | CC6.8, CC9.1 | 12.6.1 | U.09.04 |
| `incident-token-revoke.sh` IR | A.5.24, A.5.26 | CC7.3, CC7.4 | 16.1.1, 16.1.5 | U.16.01 |
| Pre-commit gates (gitleaks etc) | A.8.28, A.8.8 | CC8.1 | 14.2.1 | U.14.01 |
| CHANGELOG + audit-trail | A.8.15 | CC7.2 | 12.4.1, 18.2.3 | U.16.01 |
| `check.sh` health audit | A.8.16, A.8.34 | CC7.1, CC7.2 | 12.4.1 | U.18.01 |
| Logrotate (28-day retention) | A.8.15 | CC7.2 | 12.4.1 | U.16.01 |

---

## ISO 27001:2022 — Annex A controls

De 2022-revisie consolideerde 114 controls naar 93 in vier thema's
(A.5 Organizational, A.6 People, A.7 Physical, A.8 Technological).
Workstation-security raakt vooral A.8.

### A.5 Organizational controls

| Control | Naam | Implementatie | Evidence |
|---|---|---|---|
| A.5.24 | Information security incident management planning and preparation | `common/incident-token-revoke.sh` — voorbereid IR-runbook met gedocumenteerde flow (capture → detect → SIGKILL → disarm → invalidate → revoke → verify) | Script + `incident-token-revoke.env.example` |
| A.5.26 | Response to information security incidents | Idem — voert de IR-stappen uit, archiveert evidence naar `/tmp/incident-<ts>/`, supports optionele mail-notificatie | Script-output + `/tmp/incident-*` directories |

### A.8 Technological controls

| Control | Naam | Implementatie | Evidence |
|---|---|---|---|
| A.8.7 | Protection against malware | ClamAV (`scan.sh` dagelijks via timer) + rkhunter (`rkhunter-check.sh` dagelijks via timer). Daemon-mode via `clamd@scan` / `clamav-daemon`. Verkregen via per-OS installer (alma/arch/ubuntu). | `systemctl status clamav-scan.timer rkhunter-check.timer` + `/var/log/clamav/daily-scan.log` + `/var/log/rkhunter.log` |
| A.8.8 | Management of technical vulnerabilities | (a) `common/update.sh` updates ClamAV signatures + rkhunter database dagelijks via `av-update.timer`. (b) `install-pm-cooldown.sh` configureert 7-daagse pakket-cooldown om malicious-package-attacks vóór ze landen. | `systemctl status av-update.timer` + `~/.npmrc` cooldown-keys + signature-timestamps via `check.sh` |
| A.8.15 | Logging | Per-component logging naar `/var/log/clamav/*.log` en `/var/log/rkhunter.log`. Logrotate (`common/logrotate.conf`) rouleert wekelijks, 4 weken bewaard. CHANGELOG.md documenteert elke wijziging aan de tool zelf. | `ls -lah /var/log/clamav/` + `cat /etc/logrotate.d/workstation-security` + repo's CHANGELOG.md |
| A.8.16 | Monitoring activities | `check.sh` als read-only audit-tool, exit-code = aantal problemen (cron/CI-bruikbaar). Verifieert services, timers, signature-leeftijd en laatste-scan-data. | `bash check.sh` output + exit-code |
| A.8.19 | Installation of software on operational systems | npm/pnpm/bun cooldown via `install-pm-cooldown.sh` voorkomt installatie van pakketversies jonger dan N dagen. Werkstation-niveau (`~/.npmrc`) plus per-project templates (`common/templates/project-*`) voor CI. | `~/.npmrc`, `~/.bunfig.toml`, project-niveau `.npmrc` |
| A.8.28 | Secure coding | Pre-commit gates (`install-shell-tools.sh` + `templates/pre-commit-config-shell.yaml.example`): shellcheck, shfmt --check, gitleaks (secret-scanning), jscpd (duplication), header-conventie validator. Gates, geen auto-fix — divergence tussen lokaal en CI wordt voorkomen. | `.pre-commit-config.yaml` in elke repo + `pre-commit run --all-files` output |
| A.8.34 | Protection of information systems during audit testing | `check.sh` is read-only; geen wijzigingen aan systeem-staat tijdens audit-runs. Dry-run-modus voor `incident-token-revoke.sh` (`--dry-run`). | Script-comments + commit-history voor read-only-bewijs |

**Gedeeltelijke / zwakke claims** (transparent over coverage):
- A.8.12 Data leakage prevention — alleen het token-leak-scenario gedekt door IR-script; algemene DLP buiten scope.
- A.8.27 Secure system architecture — pre-commit gates dragen indirect bij, maar workstation-security is geen architecture-tool.

---

## SOC 2 — Trust Services Criteria (2017)

Workstation-security raakt vooral de Common Criteria CC6 (Logical Access)
en CC7 (System Operations). CC8 (Change Management) raakt het ook
indirect via de pre-commit gate-philosophy.

### CC6 — Logical and Physical Access Controls

| Criterion | Verkorte tekst | Implementatie |
|---|---|---|
| CC6.6 | Implements logical access security ... including measures to ... mitigate the risks ... such as introduction of malicious software | ClamAV + rkhunter + cooldown — drie lagen tegen malware-introductie (zie A.8.7 / A.8.8 hierboven). |
| CC6.8 | Implements controls to prevent or detect and act upon the introduction of unauthorized or malicious software | (a) ClamAV scan met wall-notificatie bij vondsten. (b) Pre-commit gitleaks vangt secrets. (c) Cooldown vangt malicious npm-uploads. (d) IR-script acteert op gedetecteerde token-compromise. |

### CC7 — System Operations

| Criterion | Verkorte tekst | Implementatie |
|---|---|---|
| CC7.1 | Use procedures, ... and software tools ... to detect changes in the configuration ... that result from ... unauthorized actions | `check.sh` audit + rkhunter rootkit-detection + ClamAV daemon. |
| CC7.2 | Monitors system components ... for anomalies indicative of malicious acts | Dagelijkse scan-logs + `check.sh` als monitoring-probe (exit-code voor cron/CI-alerting). Logrotate behoudt 28 dagen historie. |
| CC7.3 | Evaluates security events to determine whether they could or have resulted in a failure | `incident-token-revoke.sh` — gestructureerd response-pad voor één specifieke event-klasse (CanisterSprawl). |
| CC7.4 | Responds to identified security incidents by executing a defined incident response program | Idem; het IR-script is letterlijk een uitgevoerd incident-response-programma met capture → detect → neutralize → verify. |

### CC8 — Change Management

| Criterion | Verkorte tekst | Implementatie |
|---|---|---|
| CC8.1 | Authorizes, designs, ... approves, and implements changes ... to ... infrastructure ... using a change management process | Pre-commit gate-philosophy: hooks zijn poortwachters, geen auto-fixers. Elke wijziging gaat via git-commit met getelde reviewer-flow (CHANGELOG-update verplicht). |

### CC9 — Risk Mitigation

| Criterion | Verkorte tekst | Implementatie |
|---|---|---|
| CC9.1 | Identifies, selects, and develops risk mitigation activities for risks arising from potential business disruptions | Supply-chain cooldown is een gedocumenteerde risk-mitigation-keuze tegen het npm-supply-chain-incident-scenario (zie threat-model.md). |

---

## NEN 7510-2:2017 — Beheersmaatregelen voor informatiebeveiliging zorg

NEN 7510-2 volgt de ISO 27002:2013 nummering. De controls hieronder zijn
de NEN-specifieke uitwerkingen.

| Control | Naam | Implementatie |
|---|---|---|
| 12.2.1 | Beheersmaatregelen tegen malware | ClamAV + rkhunter, dagelijks via timers. (zie A.8.7 ISO 27001-mapping voor evidence-paden) |
| 12.4.1 | Logboekregistratie van gebeurtenissen | `/var/log/clamav/*` + `/var/log/rkhunter.log` + `check.sh` rapportage + CHANGELOG. Logrotate 28 dagen. |
| 12.4.3 | Logboeken van beheerders en systeembeheerders | systemd journal vangt timer-execution-events; `journalctl --user -u av-update.timer` (per user-systemd installatie). |
| 12.6.1 | Beheer van technische kwetsbaarheden | (a) `update.sh` voor signatures. (b) `install-pm-cooldown.sh` voor supply-chain. (c) `update.sh` probeert ontbrekende `rkhunter` op te halen als 'ie via pkg-manager beschikbaar komt. |
| 14.2.1 | Beleid voor beveiligd ontwikkelen | Pre-commit gates dwingen baseline-kwaliteit af: shellcheck, secret-scanning (gitleaks), formatter-check (shfmt --check), duplication-detection (jscpd). |
| 16.1.1 | Verantwoordelijkheden en procedures bij informatiebeveiligingsincidenten | `incident-token-revoke.sh` — gedocumenteerde procedure voor één specifieke incident-klasse. |
| 16.1.5 | Respons op informatiebeveiligingsincidenten | Idem — uitvoerbaar incident-response-script met capture, detect, neutralize, verify-stappen. |
| 18.2.3 | Beoordeling van technische naleving | `check.sh` als geautomatiseerde technische-naleving-check; output is auditable. |

**NEN 7510-specifieke aandachtspunten:**
- 11.2.6 (Beveiliging van apparatuur en bedrijfsmiddelen buiten gebouwen):
  voor zorginstellingen extra relevant op laptops in patiëntenzorg-contexten —
  workstation-security dekt dit niet (zou disk-encryption + remote-wipe
  vereisen).
- 14.1.3 (Bescherming van transacties): niet van toepassing op een
  workstation-tool.

---

## BIO — Baseline Informatiebeveiliging Overheid

BIO volgt ISO 27002 nummering met overheids-specifieke uitwerkingen.
Hieronder de BIO-controls die workstation-security dekt; nummers met U.
zijn de uitwerkingen, met B. de basismaatregelen.

| Control | Naam | Implementatie |
|---|---|---|
| U.07.03 | Antimalware-software | ClamAV + rkhunter via systemd timers — automatische dagelijkse scans + signature-updates. |
| U.09.04 | Patchmanagement | (a) `update.sh` daily voor AV-signatures. (b) `install-pm-cooldown.sh` voor pakket-cooldown — voorkomt installatie van te-vers/malicious packages. |
| U.14.01 | Beveiligd ontwikkelen | Pre-commit gates: shellcheck + shfmt + gitleaks + jscpd. Gate-philosophy (geen auto-fix) voorkomt stille divergence. |
| U.16.01 | Beheer van logboeken | Per-component logs + logrotate 28-day retention. Auditeerbaar via `check.sh`. |
| U.16.02 | Beveiligingsincidenten | `incident-token-revoke.sh` als specifieke incident-procedure. Algemener IR-beleid moet elders (organisatie-niveau, niet workstation-tool). |
| U.18.01 | Naleving wet- en regelgeving | `check.sh` als automatiseerbare compliance-check + CHANGELOG voor audit-traceerbaarheid van wijzigingen aan de tool. |

---

## Gaps

Controls die *typisch* in een audit-scope vallen voor een developer
workstation maar die workstation-security **niet dekt**:

| Gap | Frameworks | Wat workstation-security wel/niet doet |
|---|---|---|
| Disk encryption (LUKS / BitLocker) | ISO 27001 A.8.24, SOC 2 CC6.1, NEN 7510 18.1.3, BIO U.05.01 | NIET geïnstalleerd. Compensating: documenteer dat de organisatie LUKS-bij-OS-install of BitLocker via group-policy verplicht stelt. Roadmap-item: optionele read-only check in `check.sh` (rapportage, geen install). |
| Firewall state (firewalld/ufw) | ISO 27001 A.8.21, BIO U.06.01 | NIET gecheckt. Compensating: organisatie-baseline-image levert firewalld/ufw active. Roadmap: `check.sh` toevoeging voor rapportage. |
| Automatische OS-security-updates | ISO 27001 A.8.8, BIO U.09.04 | NIET geconfigureerd. Distro-niveau (dnf-automatic, unattended-upgrades) is verwacht; Arch is expliciet manual (rolling-release-keuze, in policy documenteren). |
| Screen-lock / clear-desk | ISO 27001 A.7.7 | NIET gecheckt. Desktop-environment-specifiek (GNOME / KDE / etc); te user-specifiek voor een baseline-tool. Documenteer in organisatie-beleid. |
| Endpoint Detection & Response (EDR) | Niet expliciet vereist door deze frameworks, maar in praktijk vaak gevraagd | NIET geïnstalleerd. Workstation-security positioneert zich expliciet als baseline, niet als EDR-vervanger (zie threat-model.md → "Out of scope"). |
| Centralized log aggregation | ISO 27001 A.8.15 voor multi-host-context, niet voor enkele workstation | NIET geconfigureerd. `wall`-notificatie is local-only. Roadmap: optionele SMTP-mail in `scan.sh` / `rkhunter-check.sh` (zelfde pattern als IR-script). |
| Multi-factor authentication (MFA) | ISO 27001 A.8.5, SOC 2 CC6.1 | Buiten scope — MFA is een directory-/IdP-keuze (Azure AD, Google Workspace), niet een workstation-tool. |
| DLP (algemene data-leak-preventie) | ISO 27001 A.8.12 | Alleen het GitHub-PAT-leak-scenario gedekt door `incident-token-revoke.sh`. Algemene DLP (USB-blokkering, clipboard-monitoring) buiten scope. |

## Evidence-collection appendix

Voor een audit-evidence-pakket: deze paden + commando's geven de
relevante state.

```bash
# Systeem-overzicht (read-only audit)
sudo bash check.sh

# Service / timer state (op systemd-systems)
systemctl status clamav-scan.timer rkhunter-check.timer av-update.timer
systemctl list-timers --all

# Live logs (afgelopen scans)
sudo ls -lah /var/log/clamav/
sudo tail -50 /var/log/clamav/daily-scan.log
sudo tail -50 /var/log/rkhunter.log

# Configured retention
cat /etc/logrotate.d/workstation-security

# Supply-chain cooldown state
bash common/install-pm-cooldown.sh --check

# Pre-commit gates aanwezig per repo
ls .pre-commit-config.yaml
pre-commit run --all-files  # → moet 5/5 groen

# Wijzigings-traceability
cat CHANGELOG.md   # in workstation-security repo
git log --oneline  # toont alle wijzigingen sinds initial install

# IR-tool dry-run (geen state-wijziging, alleen detectie-output)
bash common/incident-token-revoke.sh --dry-run
```

Voor controls die geen direct evidence-pad hebben (organisatie-beleid,
training, etc.): die horen in een organisatie-breed informatie-
beveiligingsbeleid, niet op een individueel werkstation.
