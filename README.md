# workstation-security

Install scripts voor ClamAV en rkhunter op Alma Linux, Arch Linux en Ubuntu/Debian.

Bedoeld als lichtgewicht compliancelaag (antiviruseis) voor developer workstations.

## Gebruik

Clone en installeer in één keer — daarna nooit meer naar omkijken.

### Aanbevolen: auto-detect OS

```bash
git clone https://github.com/conduction-it/workstation-security.git
cd workstation-security
sudo bash bootstrap.sh
```

`bootstrap.sh` leest `/etc/os-release` en dispatched naar de juiste installer
(alma/arch/ubuntu). Bij onbekend OS valt het terug op `ID_LIKE` en print
anders een heldere foutmelding.

### Of: directe per-OS installer

```bash
# Alma / Rocky / CentOS / RHEL / Fedora
sudo bash alma/install.sh

# Arch / Manjaro / EndeavourOS
sudo bash arch/install.sh

# Ubuntu / Debian / Mint / Pop / Raspbian
sudo bash ubuntu/install.sh
```

Na installatie draait alles automatisch via systemd timers. Geen verdere actie nodig.

## Wat wordt er geïnstalleerd?

| Package     | Functie                          |
|-------------|----------------------------------|
| `clamav`    | Antivirus scanner                |
| `clamd`     | Daemon voor realtime scanning    |
| `rkhunter`  | Rootkit detectie                 |

## Na installatie

Alles loopt automatisch via systemd timers:

| Timer                    | Wanneer         | Wat                             |
|--------------------------|-----------------|----------------------------------|
| `av-update.timer`        | Dagelijks 04:00 | Signatures + rkhunter database  |
| `clamav-scan.timer`      | Dagelijks 02:00 | Volledige scan van `/home`      |
| `rkhunter-check.timer`   | Dagelijks 03:00 | Rootkit check                   |

Bij vondsten ontvangen ingelogde gebruikers een `wall`-melding.

Logs worden automatisch geroteerd via logrotate (wekelijks, 4 weken bewaard).

## Status check

```bash
sudo bash check.sh
```

Toont services / timers / signatures / laatste scans. Exit-code is gelijk
aan het aantal gevonden problemen (capped op 2), zodat het in cron of CI
gebruikt kan worden als gezondheids-probe.

## Handmatige scan

```bash
# Volledige scan
sudo clamscan -r /home --infected --log=/var/log/clamav/manual-scan.log

# rkhunter check
sudo rkhunter --check --skip-keypress
```

## Incident response — GitHub-token dead-man's switch

Voor het CanisterSprawl-scenario (gestolen GitHub-PAT met dead-man's switch
die `rm -rf ~/` triggert bij token-revoke):

```bash
bash common/incident-token-revoke.sh --dry-run   # alleen detectie
bash common/incident-token-revoke.sh             # volledige flow
```

Werkt user-level (geen root nodig). Vangt eerst de huidige `gh`-token op
(hash + last-4) voor latere verify, detecteert IOC's + heuristisch, kill't
polling-processen met **SIGKILL voordat** systemd er een SIGTERM op stuurt
(een TERM-trap in de payload kan namelijk alsnog `rm -rf ~/` triggeren),
archiveert artefacten naar `/tmp/incident-<ts>/` (overleeft `rm -rf ~/`),
maakt de token op deze machine onbruikbaar, en wacht op handmatige revoke
op github.com/settings/tokens (er is geen user-self-revoke REST endpoint).

Schone runs laten niks achter op disk; alleen bij findings wordt
`/tmp/incident-<ts>/` aangemaakt.

### Optionele mail-rapportage

Standaard blijft alles lokaal. Voor een SMTPS-mail (bv. Gmail) na afloop:

```bash
mkdir -p ~/.config/workstation-security
cp common/incident-token-revoke.env.example ~/.config/workstation-security/mail.env
chmod 600 ~/.config/workstation-security/mail.env
$EDITOR ~/.config/workstation-security/mail.env
```

Het script weigert te mailen als die file niet op mode 600/400 staat
(bevat een App Password).

## Package-manager cooldown (npm / pnpm / bun)

Een 7-daagse quarantine op verse pakketversies verdedigt tegen
supply-chain attacks (npm yankt malicious versies doorgaans binnen 24-48u —
een 7-daagse cooldown houdt ze buiten je lockfile vóór ze opgemerkt worden).

```bash
bash common/install-pm-cooldown.sh             # default 7 dagen
bash common/install-pm-cooldown.sh --days 14   # andere window
bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen
```

Idempotent en user-level (geen sudo). Schrijft naar:

| File              | Key                            | Eenheid  | Manager       |
|-------------------|--------------------------------|----------|---------------|
| `~/.npmrc`        | `min-release-age`              | dagen    | npm 11.10+    |
| `~/.npmrc`        | `minimum-release-age`          | minuten  | pnpm 10.16+   |
| `~/.bunfig.toml`  | `[install] minimumReleaseAge`  | seconden | bun 1.3+      |

Bestaande inhoud (auth tokens, registries, custom keys) en file-mode blijven
behouden. Voor een spoedige CVE-fix die binnen het venster valt: per-project
override via een lokale `.npmrc` / `bunfig.toml` met de waarde op `0`.

### Per-project + CI

`~/.npmrc` dekt alleen je eigen workstation. CI-runners draaien als een
andere user zonder dit home-config, dus de cooldown is daar bypassed —
precies waar supply-chain attacks in production builds landen. Drop
daarom een **project-lokale** config in elke Node/Bun repo die je owned:

```bash
cp common/templates/project-npmrc.example         <jouw-repo>/.npmrc
cp common/templates/project-bunfig.toml.example   <jouw-repo>/bunfig.toml
# committen — beide files bevatten geen secrets
```

Voor projecten waar je geen file mag committen (gedeeld met teams die
deze opinie niet delen): in plaats daarvan CI env vars zetten —
`NPM_CONFIG_MIN_RELEASE_AGE=7` en `NPM_CONFIG_MINIMUM_RELEASE_AGE=10080`.
Zie `common/templates/README.md` voor de volledige uitleg.

## Handmatige update

```bash
sudo bash common/update.sh
```

## Verwijderen

```bash
sudo bash common/uninstall.sh
```

Dit verwijdert de systemd timers en logrotate config. ClamAV en rkhunter packages blijven staan — verwijder die handmatig als gewenst.
