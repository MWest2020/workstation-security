#!/usr/bin/env bash
# check.sh — controleer of ClamAV en rkhunter correct draaien
set -euo pipefail

PASS="✓"
FAIL="✗"
WARN="!"
errors=0

echo ""
echo "=== workstation-security status ==="
echo ""

echo "Services:"

# Detecteer welke ClamAV service-naam actief is (Alma vs Arch)
for svc in clamav-freshclam clamd@scan clamav-daemon; do
  # Sla over als unit niet bestaat op dit systeem
  if ! systemctl list-units --full --all 2>/dev/null | grep -q "^$svc\b\|^  $svc"; then
    continue
  fi
  status=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  if [[ "$status" == "active" ]]; then
    echo "  $PASS $svc"
  else
    echo "  $FAIL $svc (inactive)"
    ((errors++)) || true
  fi
done

echo ""
echo "Timers:"

for timer in av-update.timer clamav-scan.timer rkhunter-check.timer; do
  status=$(systemctl is-active "$timer" 2>/dev/null || echo "inactive")
  if [[ "$status" == "active" ]]; then
    echo "  $PASS $timer"
  else
    echo "  $FAIL $timer (inactive)"
    ((errors++)) || true
  fi
done

echo ""
echo "Signatures:"

if [[ -f /var/lib/clamav/main.cvd ]] || [[ -f /var/lib/clamav/main.cld ]]; then
  # shellcheck disable=SC2012  # bekend pad, geen speciale tekens
  sig_file=$(ls -t /var/lib/clamav/main.c?d 2>/dev/null | head -1)
  sig_age=$(( ( $(date +%s) - $(stat -c %Y "$sig_file") ) / 86400 ))
  if [[ $sig_age -le 3 ]]; then
    echo "  $PASS ClamAV signatures (${sig_age} dagen oud)"
  else
    echo "  $WARN ClamAV signatures (${sig_age} dagen oud — voer 'sudo freshclam' uit)"
    ((errors++)) || true
  fi
else
  echo "  $FAIL ClamAV signatures niet gevonden"
  ((errors++)) || true
fi

if command -v rkhunter &>/dev/null; then
  if [[ -r /var/lib/rkhunter/db/rkhunter.dat ]]; then
    rk_age=$(( ( $(date +%s) - $(stat -c %Y /var/lib/rkhunter/db/rkhunter.dat) ) / 86400 ))
    if [[ $rk_age -le 3 ]]; then
      echo "  $PASS rkhunter database (${rk_age} dagen oud)"
    else
      echo "  $WARN rkhunter database (${rk_age} dagen oud — voer 'sudo rkhunter --update' uit)"
      ((errors++)) || true
    fi
  elif [[ $EUID -ne 0 ]] && [[ -d /var/lib/rkhunter ]]; then
    echo "  $WARN rkhunter database niet leesbaar (voer uit als root voor volledige check)"
  else
    echo "  $FAIL rkhunter database niet gevonden"
    ((errors++)) || true
  fi
else
  echo "  - rkhunter niet geïnstalleerd (optioneel)"
fi

echo ""
echo "Laatste scans:"

if [[ -f /var/log/clamav/daily-scan.log ]]; then
  scan_date=$(stat -c %y /var/log/clamav/daily-scan.log | cut -d' ' -f1)
  echo "  $PASS ClamAV scan (laatst: $scan_date)"
else
  echo "  $WARN ClamAV scan nog nooit gedraaid (eerste scan om 02:00)"
fi

if command -v rkhunter &>/dev/null; then
  if [[ -f /var/log/rkhunter.log ]]; then
    rk_date=$(stat -c %y /var/log/rkhunter.log | cut -d' ' -f1)
    echo "  $PASS rkhunter check (laatst: $rk_date)"
  else
    echo "  $WARN rkhunter check nog nooit gedraaid (eerste check om 03:00)"
  fi
else
  echo "  - rkhunter niet geïnstalleerd (optioneel)"
fi

echo ""
if [[ $errors -eq 0 ]]; then
  echo "Alles in orde."
else
  echo "$errors probleem/problemen gevonden."
fi
echo ""
