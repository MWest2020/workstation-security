# workstation-security

Install scripts voor ClamAV en rkhunter op Alma Linux en Arch Linux.

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

## Handmatige update

```bash
sudo bash common/update.sh
```

## Verwijderen

```bash
sudo bash common/uninstall.sh
```

Dit verwijdert de systemd timers en logrotate config. ClamAV en rkhunter packages blijven staan — verwijder die handmatig als gewenst.
