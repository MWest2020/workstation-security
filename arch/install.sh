#!/usr/bin/env bash
# install.sh — ClamAV + rkhunter voor Arch Linux (pacman)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash arch/install.sh" >&2
  exit 1
fi

CLAMAV_OK=0
RKHUNTER_OK=0

echo "==> Packages installeren..."
if pacman -Sy --noconfirm clamav; then
  CLAMAV_OK=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

if pacman -S --noconfirm rkhunter 2>/dev/null; then
  RKHUNTER_OK=1
else
  echo "  rkhunter niet beschikbaar via pacman — wordt overgeslagen."
fi

echo "==> ClamAV configureren..."
mkdir -p /var/lib/clamav
chown clamav:clamav /var/lib/clamav

echo "==> Signatures downloaden..."
freshclam

echo "==> Services aanzetten..."
systemctl enable --now clamav-daemon
systemctl enable --now clamav-freshclam

if [[ $RKHUNTER_OK -eq 1 ]]; then
  echo "==> rkhunter initialiseren..."
  rkhunter --update
  rkhunter --propupd
fi

echo "==> Timers installeren..."
bash "$(dirname "$0")/../common/install-timers.sh"

echo ""
echo "=== Installatie resultaat ==="
[[ $CLAMAV_OK -eq 1 ]]   && echo "  [OK]   ClamAV"   || echo "  [FAIL] ClamAV"
[[ $RKHUNTER_OK -eq 1 ]] && echo "  [OK]   rkhunter" || echo "  [SKIP] rkhunter (niet beschikbaar via pacman)"
echo ""
echo "Voer 'sudo bash check.sh' uit voor statusoverzicht."

exit 0
