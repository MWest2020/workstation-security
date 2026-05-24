#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Ubuntu/Debian (apt).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash ubuntu/install.sh    # apt install ClamAV + rkhunter, enable services, install timers

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../common/install-base.sh"

require_root "ubuntu/install.sh"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
apt-get update
if apt-get install -y clamav clamav-daemon; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> Services aanzetten..."
# clamav-freshclam.service uit zetten — av-update.timer doet de signature-
# update om 04:00; twee mechanismen race'n op de freshclam log-lock.
disable_freshclam_daemon
enable_clamav_services clamav-daemon

echo "==> rkhunter installeren..."
if apt-get install -y rkhunter 2>/dev/null; then
  rkhunter_init
  rkhunter_ok=1
else
  echo "  rkhunter niet beschikbaar via apt — wordt overgeslagen."
fi

echo "==> Timers installeren..."
install_timers

print_summary "$clamav_ok" "$rkhunter_ok" "apt"

exit 0
