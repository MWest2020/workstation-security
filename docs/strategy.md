# Install-strategie

Hoe deze repo zich gedraagt wanneer een gebruiker hem clonet en op een
nieuwe machine draait. Bedoeld voor implementatie-engineers en mensen die
de tool overnemen: wat moet werken, wat mag falen, en hoe zie je achteraf
wat je gekregen hebt.

## Filosofie — best-effort, opt-out per component

Een verse `git clone` + `sudo bash bootstrap.sh` moet **doen wat kan en
melden wat niet ging** op de huidige distro + runtime. Componenten zijn
additief, niet wederzijds-vereist:

- Falen van een optionele component (rkhunter, logrotate-systemd) is **geen
  reden om de installer te stoppen**.
- Falen van een vereiste component (ClamAV-scanner, signatures) is dat wél
  — `bootstrap.sh` retourneert non-zero zodat een ops-flow het opmerkt.
- Iedere `install.sh` print per stap wat ging en wat niet; eindigt met
  een `print_summary` met de `✓`/`✗`-status per component.
- `check.sh` rapporteert daarna onafhankelijk de **actuele** runtime-staat,
  niet de bedoelde — drift tussen "we installeerden X" en "X draait nu"
  wordt zichtbaar.

Audit-trail: iedere afwijking van het verwachte plaatje hoort op te lossen
zijn met `check.sh`-output + een commit-message in `CHANGELOG.md`. Geen
silent skips, geen hidden state.

## Componenten en hun status

| Component | Status | Default-source | Wat gebeurt er als hij ontbreekt? |
|---|---|---|---|
| ClamAV (`clamscan`, `clamd`) | **Required** | distro-stock pkg | Installer aborteert met exit 2 (kritieke functie ontbreekt) |
| ClamAV scan-daemon (`clamd@scan` op Alma; `clamav-daemon` op Arch/Ubuntu) | **Required** | distro-stock | Installer `enable_clamav_services` faalt zichtbaar; `check.sh` rapporteert `✗` |
| ClamAV signatures via `av-update.timer` | **Required** | repo-shipped unit | Geen verse signatures → `check.sh` warning na 3+ dagen; cron-mail bij elke run |
| rkhunter | **Optional** | distro-stock (op Alma via EPEL) | Installer print uitleg, zet `rkhunter_ok=0`, gaat door; `check.sh` skipt rkhunter-secties |
| rkhunter property-database (`/var/lib/rkhunter/db/rkhunter.dat`) | Optional (vereist rkhunter) | gegenereerd door `rkhunter --propupd` in `rkhunter_init` | `check.sh` (als root) rapporteert `✗ rkhunter database niet gevonden` met retry-hint |
| systemd-timers (`av-update`, `clamav-scan`, `rkhunter-check`) | **Required if systemd** | repo-shipped units | WSL zonder systemd: skip + WSL-uitleg; native zonder systemd: skip + handmatige-commando's |
| Logrotate config (`/etc/logrotate.d/workstation-security`) | Required if systemd | repo-shipped | Logs groeien onbeperkt — zichtbaar in `du`, niet in `check.sh` |
| IR-tooling (`incident-token-revoke.sh`, `install-pm-cooldown.sh`) | Optional | repo-shipped | Niet gerund tijdens install; expliciete user-action |

## Failure-modes per component

### ClamAV (required)

- **Pakket niet beschikbaar** → installer print foutmelding + `exit 2`. Audit: het is een non-conformity op iedere framework dat AV vereist.
- **Daemon-package missing** (clamd op Alma, clamav-daemon op Ubuntu) → idem.
- **freshclam-signature-download faalt** → installer logt `freshclam_safe`-output; signatures kunnen later via `sudo bash common/update.sh` of `av-update.timer` (04:00).
- **SELinux blokkeert clamscan op `/home`** (Alma) → installer zet `setsebool -P antivirus_can_scan_system 1`. Als `setsebool` ontbreekt: warning, scan zou stil falen met "0 dirs / 0 files".

### rkhunter (optional)

- **Pakket niet beschikbaar** (b.v. EPEL niet ingeschakeld op Alma) → installer print de exacte dnf/apt/pacman-fout (geen `2>/dev/null`-mute), zet `rkhunter_ok=0`, gaat door.
- **`rkhunter_init` non-zero exit** → de wrapper rond `rkhunter --update && rkhunter --propupd` zit in `common/install-base.sh::rkhunter_init` en is defensief tegen rkhunter 1.4's deprecated-egrep-quirk: beide commands lopen onder `set +e`, return-code wordt apart bekeken, en bij niet-nul print de installer een retry-hint (`sudo rkhunter --propupd`).
- **WSL** → `rkhunter-check.sh` skipt expliciet (false-positives op /proc en init); zie `threat-model.md` voor reasoning.

### Systemd timers

- **WSL zonder `[boot] systemd=true`** → `install-timers.sh` skipt cleanly met opt-in-instructie; handmatige scans/update via `common/scan.sh` en `common/update.sh` blijven werken.
- **Native zonder systemd** (zeldzaam) → zelfde skip-pad, generic warning.

### freshclam-daemon redundantie (historisch)

De OS-stock `clamav-freshclam.service` (long-running signature-update-daemon) wordt door deze repo **niet** gebruikt — `av-update.timer` (04:00) is het enige signature-update-mechanisme. `disable_freshclam_daemon` in `install-base.sh` schakelt 'm uit op installatie. Re-enable-risico per distro staat in de comment van die functie en in CHANGELOG 2026-05-24. Reden: twee mechanismen racen op de freshclam log-lock, en `freshclam_safe` kan de daemon na een stop niet betrouwbaar herstarten.

## Per OS × runtime — verwacht eindplaatje

`✓` = werkt automatisch. `manual` = installer print instructie, gebruiker doet één commando. `skip` = bewust uit, zie threat-model.

| Component | Alma 10 native | Arch native | Ubuntu native | WSL2 zonder systemd | WSL2 met systemd |
|---|---|---|---|---|---|
| ClamAV scanner + signatures | ✓ | ✓ | ✓ | ✓ | ✓ |
| ClamAV daemon | ✓ | ✓ | ✓ | manual | ✓ |
| systemd-timers | ✓ | ✓ | ✓ | skip + opt-in-hint | ✓ |
| `check.sh` services/timers | ✓ | ✓ | ✓ | skip met uitleg | ✓ |
| rkhunter pkg + init | ✓ (via EPEL) | ✓ | ✓ | ✓ (binary) | ✓ |
| `rkhunter-check.sh` daily | ✓ | ✓ | ✓ | skip (bewust) | skip (bewust) |
| IR-tool clipboard/URL | ✓ | ✓ | ✓ | ✓ + Windows-hints | ✓ + Windows-hints |

## Hoe `check.sh` past in deze strategie

`check.sh` is **de canonieke runtime-rapportage**, niet `print_summary` van de installer. Vier statussen:

- `✓` — component draait of is vers (audit-evidence).
- `!` — afwijking die de gebruiker zou moeten oplossen, maar het systeem werkt (b.v. signatures 4 dagen oud, rkhunter-db niet leesbaar zonder root). Telt in de eindtelling.
- `✗` — kritieke afwijking (scan-daemon dood, signatures helemaal weg). Telt in de eindtelling.
- `-` — bewust overgeslagen (rkhunter op WSL, services op niet-systemd).

Eindblok somt iedere `!`/`✗` op zodat een cron-mail of audit-screenshot direct laat zien wat te doen. Exit-code is gelijk aan het aantal problemen (gecapt op 2 — bash exit-codes boven 125 hebben speciale betekenis).

## Handmatig bijwerken na een partial install

`bootstrap.sh` herhalen is altijd veilig — alle installer-paden zijn idempotent. Maar bij gerichte fixes:

| `check.sh` zegt | Wat te doen |
|---|---|
| `✗ <daemon> (inactive)` | `sudo systemctl start <daemon>`; check journal voor reden van crash |
| `! ClamAV signatures (N dagen oud)` | `sudo bash common/update.sh` — of wacht tot 04:00 |
| `✗ ClamAV signatures niet gevonden` | `sudo freshclam` (in disable-d-daemon-modus); herinstalleer als dat faalt |
| `✗ rkhunter database niet gevonden` | `sudo rkhunter --propupd` — rebuild de property-DB |
| `! rkhunter database niet leesbaar` | Geen actie nodig — alleen root kan deze file lezen; draai `check.sh` met `sudo` |
| `✗ <timer> (inactive)` | `sudo systemctl enable --now <timer>`; check `install-timers.sh`-output |

Bij twijfel: `sudo bash bootstrap.sh` opnieuw — idempotent en print per stap wat al klopt.

## Wat deze strategie níet probeert

- **Geen geforceerde alignment.** Als een component op een distro echt niet beschikbaar is (b.v. een toekomstige Alma zonder EPEL-rkhunter), proberen we geen handmatige tarball-install of vendoring. De installer slaat over en `check.sh` rapporteert het — de gebruiker beslist.
- **Geen retries op netwerk-flakes.** `freshclam` mislukt soms door CDN-blips; we vertrouwen op de daily timer voor recovery.
- **Geen rollback.** Een mislukte install laat de partial state achter. `common/uninstall.sh` is er voor om de repo-eigen units/logrotate-config schoon op te ruimen; OS-packages blijven staan tenzij de gebruiker ze handmatig verwijdert.
- **Geen "vendor your own clamav".** Als de distro-stock-versie te oud is, is dat een distro-keuze; we forken hem niet.

## Wijzigen van deze strategie

Een nieuwe component of een verandering in required/optional-status komt
op vier plekken samen:

1. **Deze doc** — tabel + failure-mode-paragraaf.
2. **`CHANGELOG.md`** — entry met datum en reden.
3. **`install.sh` per OS** — installer-pad voor de nieuwe component.
4. **`check.sh`** — runtime-rapportage (`ws_ok`/`record_fail`/`ws_skip`).

Vergeet er één en je krijgt drift tussen documentatie en werkelijkheid — exact wat deze strategie probeert te voorkomen.
