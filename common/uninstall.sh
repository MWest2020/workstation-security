#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# uninstall.sh — verwijder systemd timers, unit files en logrotate config.
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash common/uninstall.sh    # disable + remove timers/services/logrotate; ClamAV/rkhunter pkg blijft

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash common/uninstall.sh" >&2
  exit 1
fi

# Op WSL zonder systemd: timer-disable/daemon-reload werken niet maar de
# unit files + logrotate config opruimen mag wel. Skip systemd-calls,
# poets verder gewoon op zodat we geen halve state achterlaten.
if ws_systemd_available; then
  echo "==> Timers stoppen en uitschakelen..."
  for unit in "${WS_TIMERS[@]}"; do
    systemctl disable --now "$unit" 2>/dev/null || true
  done
else
  if ws_is_wsl; then
    ws_skip "WSL zonder systemd — timer disable overgeslagen (unit files worden wel verwijderd)."
  else
    ws_skip "systemd niet actief — timer disable overgeslagen."
  fi
fi

echo "==> Unit files verwijderen..."
for unit in "${WS_TIMERS[@]}" "${WS_SERVICES_GENERATED[@]}"; do
  rm -f "/etc/systemd/system/$unit"
done

echo "==> Logrotate config verwijderen..."
rm -f /etc/logrotate.d/workstation-security

if ws_systemd_available; then
  systemctl daemon-reload
fi

echo ""
echo "Timers en unit files verwijderd."
echo "ClamAV en rkhunter packages zijn NIET verwijderd — doe dit handmatig als gewenst."
