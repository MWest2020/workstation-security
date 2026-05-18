# Threat model

Wat verdedigt workstation-security wel en niet, en waarom. Bedoeld om
implementatie-engineers en security-reviewers in 15 minuten een eerlijk
beeld te geven, zodat verwachtingen niet uit elkaar lopen tussen "wat we
geïnstalleerd hebben" en "wat we daarmee oplossen".

## Doelgroep en operating assumptions

- **Workstation, geen server.** De aanname is een developer-laptop of
  -desktop met één primaire gebruiker die grotendeels root is op de eigen
  machine. Server-hardening (auditd-baselines, SELinux mandatory policies,
  agent-based EDR) is buiten scope.
- **Gebruiker is technisch competent.** De gebruiker leest commit-messages,
  begrijpt `sudo`, weet wat een GitHub PAT is. Geen kindersloten.
- **Werkstation hangt aan internet en raakt code.** Geen air-gapped
  enclave, geen kiosk-modus. Compileert, draait `npm install`, gebruikt
  `gh`. Het bedreigingsmodel is dáár-omheen.
- **Compliance is een aanleiding, geen einddoel.** De controls zijn er
  omdat ISO 27001 / SOC 2 / NEN 7510 / BIO ze vragen — niet omdat ze de
  meest waarschijnlijke aanval voorkomen. Belangrijk: een dev-machine met
  ClamAV is niet veiliger op het commodity-malware-front (linux-malware
  is zeldzaam), maar het is wel aantoonbaar in scope.

## In scope — wat we wél verdedigen

### Commodity Linux-malware

**Wat:** Klassieke virussen, trojans, ransomware-payloads die via download
of email-bijlage op een Linux dev-machine landen.

**Defense:**
- `clamscan` dagelijks op `/home` (`scan.sh` via systemd timer).
- ClamAV daemon (`clamd@scan` of `clamav-daemon`) voor realtime-mogelijkheden.
- `wall`-notificatie bij vondsten (visible alleen voor ingelogde sessies —
  zie gaps).

**Eerlijk:** linux-malware op een dev-machine is laag in waarschijnlijkheid.
De primaire reden om dit te draaien is **aantoonbaarheid voor audit**
(A.8.7 / CC6.8 / NEN 7510 12.2 / BIO U.07.03), niet "Conficker stoppen".

### Rootkits op de Linux-host

**Wat:** Persistence-tooling die zich onder het OS verbergt (LD_PRELOAD
hooks, kernel modules, modified system binaries).

**Defense:**
- `rkhunter --check` dagelijks (`rkhunter-check.sh` via systemd timer).
- `wall`-melding bij waarschuwingen.

**Eerlijk:** rkhunter is signature-based en mist moderne rootkits. Voor
serieuze rootkit-detectie heb je een EDR of YARA-based tooling nodig.
Dit is hier het minimum dat een auditor verwacht te zien onder "rootkit
detectie".

**Niet op WSL** — daar zijn de false-positives zo hoog dat alarm-fatigue
de hele control ondermijnt (zie `README.md` → WSL Support).

### Supply-chain attacks via npm / pnpm / bun

**Wat:** Een aanvaller publiceert een kwaadaardige versie van een legitiem
pakket (event-stream, ua-parser-js, node-ipc patronen) of een typosquat.
Die versie wordt geïnstalleerd op een dev-machine en draait
postinstall-scripts.

**Defense:**
- 7-daagse cooldown (`install-pm-cooldown.sh`) — refuseert pakketversies
  jonger dan N dagen. npm yankt kwaadaardige uploads doorgaans binnen
  24-48 uur; een 7-daags venster vangt ze vóór ze in lockfiles landen.
- `~/.claude/CLAUDE.md` rule: `npm ci --ignore-scripts` is de baseline,
  postinstall expliciet aanzetten per package.
- Pre-commit `gitleaks` hook (via `install-shell-tools.sh`) — vangt
  secrets die per ongeluk in `node_modules/`-paden gecommit zouden worden.

**Eerlijk:** een aanvaller met geduld kan de cooldown afwachten. Het is
**defense in depth**, niet absolutie. Tegen een gerichte attack op een
specifieke organisatie helpt dit nauwelijks.

### Gestolen GitHub PAT met dead-man's switch

**Wat:** Een aanvaller compromiteert een gh-PAT en installeert een
service die periodiek `api.github.com/user` polt. Wanneer de gebruiker
de token probeert te revoken (HTTP 40x), triggert de service `rm -rf
~/` (CanisterSprawl-klasse aanval, carlini-analyse 2026-05-12).

**Defense:**
- `incident-token-revoke.sh` — capture-eerst (sha256 + last4 voor verify),
  detecteer IOCs + heuristisch, **SIGKILL voordat systemctl stop** (anders
  vangt een TERM-trap het signaal en triggert alsnog `rm -rf`), evidence
  buiten `$HOME` (in `/tmp/incident-<ts>/` zodat het de delete-window
  overleeft), manual revoke + verify.
- Op WSL: scope-warning bij start dat Windows-host persistence (Task
  Scheduler, HKCU Run-keys, startup folder) buiten dit script valt.

**Eerlijk:** dit is een **specifieke aanval-klasse**, geen algemene
IR-flow. Andere token-compromises (AWS IAM keys, Slack bot tokens) zijn
hier niet door gedekt — die hebben hun eigen runbook nodig.

### Audit-trail van wat er op het systeem geconfigureerd is

**Wat:** Een auditor vraagt "wat draait er op deze workstation, wanneer
is dat gewijzigd, en wat doet het".

**Defense:**
- `CHANGELOG.md` met dated entries per wijziging.
- `check.sh` als read-only audit-tool met deterministic exit-code.
- `# role:` marker op elk script — `grep -rn '^# role:' scripts/` geeft
  in één scan de complete process-boundaries map.
- Logrotate op `/var/log/clamav/` en `/var/log/rkhunter.log` (28 dagen
  bewaard).

## Out of scope — wat we expliciet NIET verdedigen

### Nation-state / APT-actoren

Implant op kernel-niveau, custom in-memory droppers, zero-day exploits.
Workstation-security is een baseline; tegen een actor met budget en
geduld werkt geen enkele kant-en-klare oplossing zonder EDR en
proactieve threat-hunting. Erken het in je risk-register;
workstation-security dekt het niet.

### Remote Access Trojans (RAT) na initial compromise

Zodra een aanvaller `bash` op de machine heeft (via phishing, browser
exploit, supply-chain), kan hij de defenses ofwel uitschakelen (root)
ofwel omzeilen (user-level persistence in `~/.local/bin` die rkhunter
mist). Het IR-script vangt één specifieke variant (gh-token-monitor);
generieke RAT-detection ligt buiten scope.

### Adversary-in-the-middle (AitM) op het netwerk

Een vijandig Wi-Fi-netwerk, gecompromiteerde proxy, of route-injection.
TLS-verificatie en VPN-keuze zijn aparte controls die elders moeten
zitten (`/etc/ssh/ssh_config`, browser TLS-settings, organisatie-VPN-
beleid). Workstation-security bemoeit zich daar niet mee.

### Social engineering

Phishing, pretexting, vishing. Mensen-aanvallen. Hier helpt geen script
tegen — alleen training en beleid.

### Fysieke aanvallen

Een aanvaller met fysieke toegang (gestolen laptop, evil-maid-attack,
USB-drop met kwaadaardige firmware). Disk-encryption is hier de relevante
control (BitLocker/LUKS), maar workstation-security **installeert geen
disk-encryption** — alleen de check ervan staat op de
follow-up-roadmap. Voor laptops in productie: gebruik LUKS of
BitLocker, los van dit script.

### Webbrowser-aanvallen

Een vijandige website die JS-engine bugs exploit, of browser-extensions
die credentials stelen. Hier zijn browser-hardening (HSTS-preload,
extension-policy via group-policy of een MDM), uBlock-Origin en een
goede password-manager de relevante controls.

### Server-side aanvallen

Een aanvaller die SSH naar deze machine probeert. SSH-hardening (key-only
auth, fail2ban, port-changes) is een aparte control. Workstation-security
gaat ervan uit dat de machine geen inbound-services exposed heeft die
publiek bereikbaar zijn — een dev-laptop, niet een server.

## Operating assumptions

Het bedreigingsmodel hangt af van deze aannames; als één ervan niet klopt
voor jouw deployment, herzie dan welke "out of scope"-items daadwerkelijk
out-of-scope blijven.

| Aanname | Wat als 'ie niet klopt? |
|---|---|
| Single primary user met root | Multi-user dev-shared-machine: rkhunter waarschuwingen kunnen elkaar overschrijven; permissions op `/var/log/clamav/` heroverwegen |
| Internet-connectivity beschikbaar | Air-gapped: cooldown en signature-updates lopen vast; offline-update-flow vereist |
| Gebruiker installeert binnen 7 dagen geen verse packages | Spoedige CVE-fix nodig: per-project `.npmrc` met `min-release-age=0`, gedocumenteerd in CHANGELOG |
| systemd is de init (of WSL2 met opt-in) | OpenRC, init.d, runit: timers werken niet; handmatige cron-installatie voor scans nodig |
| `/home` is op een non-network filesystem | NFS-mounted home: ClamAV scan kan uren duren; pas `scan.sh` exclude-patterns aan |
| Wall-notificatie bereikt de gebruiker | Headless / cloud-IDE-omgeving: vondsten verdwijnen ongezien; voeg mail-rapportage toe (zie `incident-token-revoke.env.example` voor het patroon) |

## Wijzigingen aan dit document

Update wanneer:
- Een nieuwe script of installer wordt toegevoegd → eventueel uitbreiden van "in scope"
- Een aanval-klasse die voorheen out-of-scope was, in scope komt → reden + defense documenteren
- Een operating assumption verandert → herziening van het out-of-scope-deel
- Een control wordt verwijderd → uitleg waarom (verplaatst naar andere tool, redundant geworden, etc.)
