#!/usr/bin/env bash
# check.sh — controleer of ClamAV en rkhunter correct draaien.
# Exit-code is gelijk aan het aantal gevonden problemen (capped op 2), zodat
# cron/CI kan detecteren wanneer er iets niet klopt.
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common/lib.sh"

errors=0

echo ""
echo "=== workstation-security status ==="
echo ""

echo "Services:"

# Eén `systemctl list-units` call, output gecapture'd in een var. Daarna
# matchen we per candidate via here-string — geen pipe, dus geen SIGPIPE-
# risico op `grep -q` (die early-exit'et bij een hit en upstream een SIGPIPE
# zou geven dat door `pipefail` als pipeline-failure binnenkomt — false skip).
units_output="$(systemctl list-units --full --all 2>/dev/null)"

# Detecteer welke ClamAV-service-naam actief is (Alma vs Arch vs Ubuntu).
for svc in "${WS_CLAMAV_DAEMON_CANDIDATES[@]}"; do
  if ! grep -qE "^${svc}\b|^  ${svc}" <<<"$units_output"; then
    continue
  fi
  status="$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")"
  if [[ "$status" == "active" ]]; then
    ws_ok "$svc"
  else
    ws_fail "$svc (inactive)"
    ((errors++)) || true
  fi
done

echo ""
echo "Timers:"

for timer in "${WS_TIMERS[@]}"; do
  status="$(systemctl is-active "$timer" 2>/dev/null || echo "inactive")"
  if [[ "$status" == "active" ]]; then
    ws_ok "$timer"
  else
    ws_fail "$timer (inactive)"
    ((errors++)) || true
  fi
done

echo ""
echo "Signatures:"

# daily wordt vrijwel dagelijks ververst, main zelden — kies de nieuwste als
# indicator voor "wanneer draaide freshclam voor het laatst succesvol".
# shellcheck disable=SC2012  # bekend pad, geen speciale tekens
sig_file=$(ls -t /var/lib/clamav/daily.c?d /var/lib/clamav/main.c?d 2>/dev/null | head -1)
if [[ -n "$sig_file" ]]; then
  sig_age=$(( ( $(date +%s) - $(stat -c %Y "$sig_file") ) / 86400 ))
  if [[ $sig_age -le 3 ]]; then
    ws_ok "ClamAV signatures (${sig_age} dagen oud)"
  else
    ws_warn "ClamAV signatures (${sig_age} dagen oud — voer 'sudo freshclam' uit)"
    ((errors++)) || true
  fi
else
  ws_fail "ClamAV signatures niet gevonden"
  ((errors++)) || true
fi

if command -v rkhunter &>/dev/null; then
  if [[ -r /var/lib/rkhunter/db/rkhunter.dat ]]; then
    rk_age=$(( ( $(date +%s) - $(stat -c %Y /var/lib/rkhunter/db/rkhunter.dat) ) / 86400 ))
    if [[ $rk_age -le 3 ]]; then
      ws_ok "rkhunter database (${rk_age} dagen oud)"
    else
      ws_warn "rkhunter database (${rk_age} dagen oud — voer 'sudo rkhunter --update' uit)"
      ((errors++)) || true
    fi
  elif [[ $EUID -ne 0 ]] && [[ -d /var/lib/rkhunter ]]; then
    ws_warn "rkhunter database niet leesbaar (voer uit als root voor volledige check)"
  else
    ws_fail "rkhunter database niet gevonden"
    ((errors++)) || true
  fi
else
  ws_skip "rkhunter niet geïnstalleerd (optioneel)"
fi

echo ""
echo "Laatste scans:"

if [[ -f /var/log/clamav/daily-scan.log ]]; then
  scan_date="$(stat -c %y /var/log/clamav/daily-scan.log | cut -d' ' -f1)"
  ws_ok "ClamAV scan (laatst: $scan_date)"
else
  ws_warn "ClamAV scan nog nooit gedraaid (eerste scan om 02:00)"
fi

if command -v rkhunter &>/dev/null; then
  if [[ -f /var/log/rkhunter.log ]]; then
    rk_date="$(stat -c %y /var/log/rkhunter.log | cut -d' ' -f1)"
    ws_ok "rkhunter check (laatst: $rk_date)"
  else
    ws_warn "rkhunter check nog nooit gedraaid (eerste check om 03:00)"
  fi
else
  ws_skip "rkhunter niet geïnstalleerd (optioneel)"
fi

echo ""
if [[ $errors -eq 0 ]]; then
  echo "Alles in orde."
  exit 0
else
  echo "$errors probleem/problemen gevonden."
  # Cap exit-code op 2 — exit-codes boven 125 hebben in shell speciale betekenis.
  exit $(( errors > 2 ? 2 : errors ))
fi
