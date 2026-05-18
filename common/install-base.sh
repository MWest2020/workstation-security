#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: library
#
# common/install-base.sh — gedeelde install-helpers voor alma/arch/ubuntu.
#
# Source dit vanuit een OS-specifiek install.sh; voer het niet zelfstandig uit.
# De OS-scripts blijven verantwoordelijk voor pkg-manager-commando's, daemon-
# naam (clamav-daemon vs clamd@scan) en OS-specifieke quirks (SELinux op Alma,
# /var/lib/clamav-chown op Arch).
#
# Style-afwijking: shebang via `env bash` voor consistentie met repo.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "error: common/install-base.sh is een library — source hem, voer niet uit." >&2
  exit 2
fi

if [[ -n "${WS_INSTALL_BASE_SOURCED:-}" ]]; then
  return 0
fi
readonly WS_INSTALL_BASE_SOURCED=1

WS_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WS_BASE_DIR

# shellcheck source=/dev/null
source "${WS_BASE_DIR}/lib.sh"

# Vereist root; toont begeleidende sudo-hint met het pad van de caller.
require_root() {
  local caller_hint="${1:-install.sh}"
  if [[ $EUID -ne 0 ]]; then
    echo "Run als root: sudo bash ${caller_hint}" >&2
    exit 1
  fi
}

# freshclam draait niet als de daemon de log-lock vasthoudt — stop hem eerst.
# Best-effort: faalt zonder error als de service niet bestaat.
freshclam_safe() {
  systemctl stop clamav-freshclam 2>/dev/null || true
  freshclam
}

# rkhunter database update + propupd. Caller bepaalt zelf of een
# distro-specifieke quirk een set +e/-e-wrapper nodig heeft (Arch ships een
# rkhunter die op deprecated egrep een non-zero terugkomt — zie arch/install.sh).
rkhunter_init() {
  rkhunter --update
  rkhunter --propupd
}

# Enable + start een lijst van clamav-gerelateerde services.
enable_clamav_services() {
  local svc
  for svc in "$@"; do
    systemctl enable --now "$svc"
  done
}

# Roep common/install-timers.sh aan. Verwacht $WS_BASE_DIR gezet (vanaf lib.sh).
install_timers() {
  bash "${WS_BASE_DIR}/install-timers.sh"
}

# Print eindresultaat met de gedeelde status-iconen. clamav_ok en rkhunter_ok
# zijn 0/1; pm_name is "dnf" / "apt" / "pacman" voor de skip-melding.
print_summary() {
  local clamav_ok="$1" rkhunter_ok="$2" pm_name="$3"
  echo ""
  echo "=== Installatie resultaat ==="
  if [[ "$clamav_ok" -eq 1 ]]; then
    ws_ok "ClamAV"
  else
    ws_fail "ClamAV"
  fi
  if [[ "$rkhunter_ok" -eq 1 ]]; then
    ws_ok "rkhunter"
  else
    ws_skip "rkhunter (niet beschikbaar via ${pm_name})"
  fi
  echo ""
  echo "Voer 'sudo bash check.sh' uit voor statusoverzicht."
}
