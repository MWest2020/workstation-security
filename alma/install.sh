#!/usr/bin/env bash
# install.sh — ClamAV + rkhunter voor Alma Linux (dnf)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash alma/install.sh" >&2
  exit 1
fi

CLAMAV_OK=0
RKHUNTER_OK=0

echo "==> Packages installeren..."
dnf install -y epel-release
if dnf install -y clamav clamd clamav-update; then
  CLAMAV_OK=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> ClamAV configureren..."
sed -i 's/^Example/#Example/' /etc/clamd.d/scan.conf
sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf
sed -i 's/^Example/#Example/' /etc/freshclam.conf

echo "==> Signatures downloaden..."
freshclam

echo "==> Services aanzetten..."
systemctl enable --now clamd@scan
systemctl enable --now clamav-freshclam

echo "==> rkhunter installeren..."
if dnf install -y rkhunter 2>/dev/null; then
  rkhunter --update
  rkhunter --propupd
  RKHUNTER_OK=1
else
  echo "  rkhunter niet beschikbaar via dnf (Alma 10?) — wordt overgeslagen."
fi

echo "==> Timers installeren..."
bash "$(dirname "$0")/../common/install-timers.sh"

echo ""
echo "=== Installatie resultaat ==="
[[ $CLAMAV_OK -eq 1 ]]   && echo "  [OK]   ClamAV"   || echo "  [FAIL] ClamAV"
[[ $RKHUNTER_OK -eq 1 ]] && echo "  [OK]   rkhunter" || echo "  [SKIP] rkhunter (niet beschikbaar via dnf)"
echo ""
echo "Voer 'sudo bash check.sh' uit voor statusoverzicht."

# Exit 0 als ClamAV OK — rkhunter is optioneel
exit 0
