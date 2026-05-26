#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# check.sh — controleer of ClamAV en rkhunter correct draaien.
# Exit-code is gelijk aan het aantal gevonden problemen (capped op 2), zodat
# cron/CI kan detecteren wanneer er iets niet klopt.
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   bash check.sh             # read-only audit; exit-code = aantal problemen (capped op 2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common/lib.sh"

ws_handle_version "$@"

errors=0
# Verzamel een korte beschrijving van iedere geconstateerde fout zodat de
# samenvatting onderaan ze opsomt — handig voor cron-mail / audit-trail
# (lezer hoeft niet terug te scrollen om de "1 probleem gevonden" te duiden).
failures=()

# Registreer een fail-conditie: print de regel via ws_fail, hou hem vast voor
# de samenvatting en hoog de error-teller op. Vervangt de inline drie-regelige
# pattern op iedere fail-call-site.
record_fail() {
  ws_fail "$1"
  failures+=("$1")
  ((errors++)) || true
}

# Identiek voor warn-condities die ook in het totaal meetellen (b.v. stale
# signature/database). Visueel rendert ws_warn als `!`, maar voor de
# audit-samenvatting is het gewoon een te-adresseren probleem.
record_warn() {
  ws_warn "$1"
  failures+=("$1")
  ((errors++)) || true
}

echo ""
echo "=== workstation-security status ==="
echo ""

# Systemd-afhankelijke secties (services + timers). Op WSL zonder
# systemd-opt-in zijn deze niet relevant — sla ze over met duidelijke uitleg
# zodat een gebruiker niet denkt dat er iets stuk is.
if ws_systemd_available; then
  echo "Services:"

  # Eén `systemctl list-units` call, output gecapture'd in een var. Daarna
  # matchen we per candidate via here-string — geen pipe, dus geen SIGPIPE-
  # risico op `grep -q` (die early-exit'et bij een hit en upstream een SIGPIPE
  # zou geven dat door `pipefail` als pipeline-failure binnenkomt — false skip).
  units_output="$(systemctl list-units --full --all 2>/dev/null)"

  # Detecteer welke ClamAV-scan-daemon actief is (Alma: clamd@scan;
  # Arch/Ubuntu: clamav-daemon). First-active-wins: zodra een candidate
  # actief is, klaar — andere candidates worden niet als fout gerapporteerd
  # ook al staan ze loaded-but-inactive in list-units (b.v. omdat een vorig
  # package-install ze ooit heeft opgestart). Maximaal 1 error uit deze sectie.
  scan_daemon_active=""
  scan_daemon_loaded=""
  for svc in "${WS_CLAMAV_DAEMON_CANDIDATES[@]}"; do
    if ! grep -qE "^${svc}\b|^  ${svc}" <<<"$units_output"; then
      continue
    fi
    scan_daemon_loaded="$svc"
    status="$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")"
    if [[ "$status" == "active" ]]; then
      scan_daemon_active="$svc"
      ws_ok "$svc"
      break
    fi
  done
  if [[ -z "$scan_daemon_active" ]]; then
    if [[ -n "$scan_daemon_loaded" ]]; then
      record_fail "$scan_daemon_loaded (inactive)"
    else
      record_fail "geen ClamAV scan-daemon gevonden (clamd@scan / clamav-daemon)"
    fi
  fi

  echo ""
  echo "Timers:"

  for timer in "${WS_TIMERS[@]}"; do
    status="$(systemctl is-active "$timer" 2>/dev/null || echo "inactive")"
    if [[ "$status" == "active" ]]; then
      ws_ok "$timer"
    else
      record_fail "$timer (inactive)"
    fi
  done
else
  echo "Services / Timers:"
  if ws_is_wsl; then
    ws_skip "WSL zonder systemd — services/timers niet van toepassing"
    ws_info "Voor automatische scans op WSL: zet [boot] systemd=true in /etc/wsl.conf"
    ws_info "en draai 'wsl --shutdown' (vanuit Windows), dan installer opnieuw."
  else
    ws_skip "systemd niet beschikbaar — services/timers niet gecheckt"
  fi
fi

echo ""
echo "Signatures:"

# daily wordt vrijwel dagelijks ververst, main zelden — kies de nieuwste als
# indicator voor "wanneer draaide freshclam voor het laatst succesvol".
# shellcheck disable=SC2012  # bekend pad, geen speciale tekens
sig_file=$(ls -t /var/lib/clamav/daily.c?d /var/lib/clamav/main.c?d 2>/dev/null | head -1)
if [[ -n "$sig_file" ]]; then
  sig_age=$((($(date +%s) - $(stat -c %Y "$sig_file")) / 86400))
  if [[ $sig_age -le 3 ]]; then
    ws_ok "ClamAV signatures (${sig_age} dagen oud)"
  else
    record_warn "ClamAV signatures (${sig_age} dagen oud — voer 'sudo freshclam' uit)"
  fi
else
  record_fail "ClamAV signatures niet gevonden"
fi

if command -v rkhunter &>/dev/null; then
  if [[ -r /var/lib/rkhunter/db/rkhunter.dat ]]; then
    rk_age=$((($(date +%s) - $(stat -c %Y /var/lib/rkhunter/db/rkhunter.dat)) / 86400))
    if [[ $rk_age -le 3 ]]; then
      ws_ok "rkhunter database (${rk_age} dagen oud)"
    else
      record_warn "rkhunter database (${rk_age} dagen oud — voer 'sudo rkhunter --update' uit)"
    fi
  elif [[ $EUID -ne 0 ]] && [[ -d /var/lib/rkhunter ]]; then
    ws_warn "rkhunter database niet leesbaar (voer uit als root voor volledige check)"
  else
    record_fail "rkhunter database niet gevonden (voer 'sudo rkhunter --propupd' uit)"
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
  echo "$errors probleem/problemen gevonden:"
  # Sommige cron-MTAs trimmen lege regels of indented output — gebruik een
  # nuchter '- '-prefix zonder kleur/iconen zodat de lijst overleeft.
  for f in "${failures[@]}"; do
    printf '  - %s\n' "$f"
  done
  # Cap exit-code op 2 — exit-codes boven 125 hebben in shell speciale betekenis.
  exit $((errors > 2 ? 2 : errors))
fi
