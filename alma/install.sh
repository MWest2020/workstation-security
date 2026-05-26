#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Alma Linux (dnf).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash alma/install.sh             # dnf install ClamAV + rkhunter, enable services, install timers
#   bash alma/install.sh --dry-run        # print zou-uitgevoerd-zijn commando's, geen wijzigingen
#   bash alma/install.sh --version        # print versie en exit

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../common/install-base.sh"

ws_parse_install_args "alma/install.sh" "$@"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
ws_run_or_print dnf install -y epel-release
if ws_is_dry_run; then
  ws_run_or_print dnf install -y clamav clamd clamav-update
  clamav_ok=1
elif dnf install -y clamav clamd clamav-update; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> ClamAV configureren..."
ws_run_or_print sed -i 's/^Example/#Example/' /etc/clamd.d/scan.conf
ws_run_or_print sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf
ws_run_or_print sed -i 's/^Example/#Example/' /etc/freshclam.conf

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> SELinux boolean voor /home scans..."
# Zonder deze boolean blokkeert SELinux clamscan (antivirus_exec_t) op /home,
# resultaat: scan eindigt met 0 dirs / 0 files / status=2 INVALIDARGUMENT.
if command -v setsebool >/dev/null 2>&1; then
  ws_run_or_print setsebool -P antivirus_can_scan_system 1
elif ws_is_dry_run; then
  echo "  would run: setsebool -P antivirus_can_scan_system 1 (when SELinux beschikbaar)"
fi

echo "==> Services aanzetten..."
# clamav-freshclam.service uit zetten. Alma's upstream systemd-preset voor
# deze unit is `disabled` (zie `systemctl show -p UnitFilePreset`), dus een
# verse dnf-install zet 'm niet aan; deze call is voor migratie van eerdere
# installs waar onze installer hem nog expliciet enable'de. av-update.timer
# (zie install_timers) is in deze repo het enige signature-update mechanisme.
disable_freshclam_daemon
enable_clamav_services clamd@scan

echo "==> rkhunter installeren..."
# Geen `2>/dev/null` op de echte run: als dnf rkhunter niet kan installeren
# willen we de reden zien (EPEL niet ingeschakeld, repo-fout, etc.) i.p.v.
# een silent skip. rkhunter_init wrapt zelf set +e/-e rond --update en
# --propupd (rkhunter 1.4 + deprecated egrep — zie install-base.sh).
if ws_is_dry_run; then
  ws_run_or_print dnf install -y rkhunter
  rkhunter_init
  rkhunter_ok=1
elif dnf install -y rkhunter; then
  if rkhunter_init; then
    rkhunter_ok=1
  else
    echo "  rkhunter init kreeg non-zero exit (zie ws_warn hierboven)."
    echo "  Controleer met:  sudo ls -l /var/lib/rkhunter/db/rkhunter.dat"
    echo "  Ontbreekt de .dat? Draai dan handmatig: sudo rkhunter --propupd"
  fi
else
  echo "  rkhunter niet beschikbaar via dnf — wordt overgeslagen."
  echo "  Op Alma 10 vereist rkhunter EPEL: 'sudo dnf install epel-release'."
fi

echo "==> Timers installeren..."
install_timers

if ws_is_dry_run; then
  echo ""
  echo "(dry-run; no changes made)"
  exit 0
fi

print_summary "$clamav_ok" "$rkhunter_ok" "dnf"

# Exit 0 als ClamAV OK — rkhunter is optioneel.
exit 0
