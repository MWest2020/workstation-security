# workstation-security

Install scripts voor ClamAV en rkhunter op Alma Linux, Arch Linux en Ubuntu/Debian.

Bedoeld als lichtgewicht compliancelaag (antiviruseis) voor developer workstations.

## Gebruik

Clone en installeer in één keer — daarna nooit meer naar omkijken.

### Alma Linux
```bash
git clone https://github.com/conduction-it/workstation-security.git
cd workstation-security
sudo bash alma/install.sh
```

### Arch Linux
```bash
git clone https://github.com/conduction-it/workstation-security.git
cd workstation-security
sudo bash arch/install.sh
```

### Ubuntu / Debian
```bash
git clone https://github.com/conduction-it/workstation-security.git
cd workstation-security
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

## Handmatige update

```bash
sudo bash common/update.sh
```

## Verwijderen

```bash
sudo bash common/uninstall.sh
```

Dit verwijdert de systemd timers en logrotate config. ClamAV en rkhunter packages blijven staan — verwijder die handmatig als gewenst.
