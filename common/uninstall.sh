#!/usr/bin/env bash
# uninstall.sh — verwijder systemd timers, unit files en logrotate config.
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash common/uninstall.sh" >&2
  exit 1
fi

echo "==> Timers stoppen en uitschakelen..."
for unit in "${WS_TIMERS[@]}"; do
  systemctl disable --now "$unit" 2>/dev/null || true
done

echo "==> Unit files verwijderen..."
for unit in "${WS_TIMERS[@]}" "${WS_SERVICES_GENERATED[@]}"; do
  rm -f "/etc/systemd/system/$unit"
done

echo "==> Logrotate config verwijderen..."
rm -f /etc/logrotate.d/workstation-security

systemctl daemon-reload

echo ""
echo "Timers en unit files verwijderd."
echo "ClamAV en rkhunter packages zijn NIET verwijderd — doe dit handmatig als gewenst."
