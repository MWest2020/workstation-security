#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Alma Linux (dnf).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash alma/install.sh    # dnf install ClamAV + rkhunter, enable services, install timers

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../common/install-base.sh"

require_root "alma/install.sh"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
dnf install -y epel-release
if dnf install -y clamav clamd clamav-update; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> ClamAV configureren..."
sed -i 's/^Example/#Example/' /etc/clamd.d/scan.conf
sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf
sed -i 's/^Example/#Example/' /etc/freshclam.conf

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> SELinux boolean voor /home scans..."
# Zonder deze boolean blokkeert SELinux clamscan (antivirus_exec_t) op /home,
# resultaat: scan eindigt met 0 dirs / 0 files / status=2 INVALIDARGUMENT.
if command -v setsebool >/dev/null 2>&1; then
  setsebool -P antivirus_can_scan_system 1
fi

echo "==> Services aanzetten..."
# clamav-freshclam.service is dnf-default enabled — uit zetten, want
# av-update.timer (zie install_timers) is in deze repo het enige signature-
# update mechanisme.
disable_freshclam_daemon
enable_clamav_services clamd@scan

echo "==> rkhunter installeren..."
if dnf install -y rkhunter 2>/dev/null; then
  rkhunter_init
  rkhunter_ok=1
else
  echo "  rkhunter niet beschikbaar via dnf (Alma 10?) — wordt overgeslagen."
fi

echo "==> Timers installeren..."
install_timers

print_summary "$clamav_ok" "$rkhunter_ok" "dnf"

# Exit 0 als ClamAV OK — rkhunter is optioneel.
exit 0
