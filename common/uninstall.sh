#!/usr/bin/env bash
# uninstall.sh — verwijder systemd timers, unit files en logrotate config
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash common/uninstall.sh" >&2
  exit 1
fi

echo "==> Timers stoppen en uitschakelen..."
for unit in av-update.timer clamav-scan.timer rkhunter-check.timer; do
  systemctl disable --now "$unit" 2>/dev/null || true
done

echo "==> Unit files verwijderen..."
for unit in av-update.service av-update.timer clamav-scan.service clamav-scan.timer rkhunter-check.service rkhunter-check.timer; do
  rm -f "/etc/systemd/system/$unit"
done

echo "==> Logrotate config verwijderen..."
rm -f /etc/logrotate.d/workstation-security

systemctl daemon-reload

echo ""
echo "Timers en unit files verwijderd."
echo "ClamAV en rkhunter packages zijn NIET verwijderd — doe dit handmatig als gewenst."
