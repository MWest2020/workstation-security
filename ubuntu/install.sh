#!/usr/bin/env bash
# install.sh — ClamAV + rkhunter voor Ubuntu/Debian (apt)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash ubuntu/install.sh" >&2
  exit 1
fi

CLAMAV_OK=0
RKHUNTER_OK=0

echo "==> Packages installeren..."
apt-get update
if apt-get install -y clamav clamav-daemon; then
  CLAMAV_OK=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> Signatures downloaden..."
# Stop freshclam service als die al draait (lock conflict)
systemctl stop clamav-freshclam 2>/dev/null || true
freshclam

echo "==> Services aanzetten..."
systemctl enable --now clamav-daemon
systemctl enable --now clamav-freshclam

echo "==> rkhunter installeren..."
if apt-get install -y rkhunter 2>/dev/null; then
  rkhunter --update
  rkhunter --propupd
  RKHUNTER_OK=1
else
  echo "  rkhunter niet beschikbaar via apt — wordt overgeslagen."
fi

echo "==> Timers installeren..."
bash "$(dirname "$0")/../common/install-timers.sh"

echo ""
echo "=== Installatie resultaat ==="
[[ $CLAMAV_OK -eq 1 ]]   && echo "  [OK]   ClamAV"   || echo "  [FAIL] ClamAV"
[[ $RKHUNTER_OK -eq 1 ]] && echo "  [OK]   rkhunter" || echo "  [SKIP] rkhunter (niet beschikbaar via apt)"
echo ""
echo "Voer 'sudo bash check.sh' uit voor statusoverzicht."

exit 0
