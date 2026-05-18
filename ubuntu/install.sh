#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Ubuntu/Debian (apt).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash ubuntu/install.sh             # apt install ClamAV + rkhunter, enable services, install timers
#   bash ubuntu/install.sh --dry-run        # print zou-uitgevoerd-zijn commando's, geen wijzigingen
#   bash ubuntu/install.sh --version        # print versie en exit

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

require_root "ubuntu/install.sh"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
ws_run_or_print apt-get update
if ws_is_dry_run; then
  ws_run_or_print apt-get install -y clamav clamav-daemon
  clamav_ok=1
elif apt-get install -y clamav clamav-daemon; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> Services aanzetten..."
enable_clamav_services clamav-daemon clamav-freshclam

echo "==> rkhunter installeren..."
if ws_is_dry_run; then
  ws_run_or_print apt-get install -y rkhunter
  rkhunter_init
  rkhunter_ok=1
elif apt-get install -y rkhunter 2>/dev/null; then
  rkhunter_init
  rkhunter_ok=1
else
  echo "  rkhunter niet beschikbaar via apt — wordt overgeslagen."
fi

echo "==> Timers installeren..."
install_timers

if ws_is_dry_run; then
  echo ""
  echo "(dry-run; no changes made)"
  exit 0
fi

print_summary "$clamav_ok" "$rkhunter_ok" "apt"

exit 0
