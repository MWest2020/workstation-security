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

ws_handle_version "$@"
for arg in "$@"; do
  case "$arg" in
    --dry-run) export WS_DRY_RUN=1 ;;
    *)
      echo "error: onbekend argument: $arg" >&2
      echo "       Geldige flags: --dry-run, --version/-V" >&2
      exit 2
      ;;
  esac
done

require_root "alma/install.sh"

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
enable_clamav_services clamd@scan clamav-freshclam

echo "==> rkhunter installeren..."
if ws_is_dry_run; then
  ws_run_or_print dnf install -y rkhunter
  rkhunter_init
  rkhunter_ok=1
elif dnf install -y rkhunter 2>/dev/null; then
  rkhunter_init
  rkhunter_ok=1
else
  echo "  rkhunter niet beschikbaar via dnf (Alma 10?) — wordt overgeslagen."
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
