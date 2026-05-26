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
# Dry-run: skip de check — een gebruiker wil ook zonder sudo kunnen voorspellen
# wat de installer zou doen (CI / audit-evidence).
require_root() {
  local caller_hint="${1:-install.sh}"
  if ws_is_dry_run; then
    return 0
  fi
  if [[ $EUID -ne 0 ]]; then
    echo "Run als root: sudo bash ${caller_hint}" >&2
    exit 1
  fi
}

# freshclam draait niet als de daemon de log-lock vasthoudt — stop hem eerst.
# Best-effort: faalt zonder error als de service niet bestaat. Sinds we
# clamav-freshclam.service zelf niet meer enable'n (zie disable_freshclam_daemon
# hieronder) is de stop-call op een verse install doorgaans een no-op, maar we
# houden hem als defensieve safety net voor (a) gemigreerde installs en (b)
# Ubuntu/Debian waar debhelper-systemd hem bij een `apt --reinstall` opnieuw
# enable kan zetten.
freshclam_safe() {
  if ws_is_dry_run; then
    ws_run_or_print systemctl stop clamav-freshclam
    ws_run_or_print freshclam
    return 0
  fi
  systemctl stop clamav-freshclam 2>/dev/null || true
  freshclam
}

# Schakel clamav-freshclam.service uit als hij door pakket-install enabled
# werd. Dit project gebruikt av-update.timer (04:00) als enige signature-
# update mechanisme — twee concurrent mechanismen race'n op de freshclam
# log-lock, en update.sh's `systemctl stop` voor freshclam_safe laat de
# daemon permanent dood achter (de service wordt nooit herstart). Eén
# mechanisme = boring & auditable.
#
# Re-enable risico per distro:
#   Alma  — preset is `disabled`; dnf install/reinstall raakt 'm niet aan.
#   Arch  — pacman draait geen preset; service is by default off.
#   Ubuntu/Debian — debhelper-systemd postinst kan bij `apt install --reinstall`
#                   van clamav-daemon de freshclam-service opnieuw enable'n;
#                   deze functie corrigeert dat als de installer opnieuw
#                   gedraaid wordt, en freshclam_safe (in update.sh) vangt
#                   het dagelijks tijdelijk op met een stop voor freshclam.
#
# Idempotent: no-op als de service niet bestaat of al disabled is, en op
# WSL zonder systemd.
disable_freshclam_daemon() {
  if ! ws_systemd_available; then
    return 0
  fi
  systemctl disable --now clamav-freshclam 2>/dev/null || true
}

# rkhunter database update + property-database (re)bouwen. rkhunter 1.4.x
# (huidig op Alma/Arch/Ubuntu) leunt intern op deprecated `egrep`; --update
# kan daardoor met non-zero exit eindigen terwijl er functioneel niets fout
# is. Onder `set -e` zou dat de erop volgende --propupd skippen, met als
# resultaat een geïnstalleerde rkhunter zonder rkhunter.dat property-
# database. `check.sh` faalt vervolgens permanent op "rkhunter database
# niet gevonden". Daarom hier defensieve set +e/-e rond beide calls.
#
# Return-code: 0 als beide commands lukten, anders 1 (caller beslist of dat
# tot rkhunter_ok=0 leidt of dat er een retry-hint geprint moet worden).
rkhunter_init() {
  if ws_is_dry_run; then
    ws_run_or_print rkhunter --update
    ws_run_or_print rkhunter --propupd
    return 0
  fi
  local update_rc propupd_rc
  set +e
  rkhunter --update
  update_rc=$?
  rkhunter --propupd
  propupd_rc=$?
  set -e
  if [[ $update_rc -ne 0 ]] || [[ $propupd_rc -ne 0 ]]; then
    ws_warn "rkhunter init: --update rc=${update_rc} --propupd rc=${propupd_rc}"
    return 1
  fi
  return 0
}

# Standaard arg-parsing voor OS-installers (alma/arch/ubuntu). Dekt:
#   --version / -V         via ws_handle_version (exit'et zelf)
#   --dry-run              zet WS_DRY_RUN=1 export
#   onbekende flags        echo error + exit 2
# Tot slot: require_root met de meegegeven script-hint (overgeslagen in
# dry-run). Eerste arg is het script-pad voor de sudo-hint ("alma/install.sh"
# etc.); resterende args zijn de originele "$@" van de caller.
#
# Reden voor consolidatie: pre-jscpd waren deze 17 regels identiek in alma/,
# arch/ en ubuntu/install.sh (one source of truth voor de arg-conventie,
# en de duplicate-detector klaagde terecht).
ws_parse_install_args() {
  local script_hint="$1"
  shift
  ws_handle_version "$@"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) export WS_DRY_RUN=1 ;;
      *)
        echo "error: onbekend argument: $arg" >&2
        echo "       Geldige flags: --dry-run, --version/-V" >&2
        exit 2
        ;;
    esac
  done
  require_root "$script_hint"
}

# Enable + start een lijst van clamav-gerelateerde services.
# Op WSL zonder systemd-opt-in: warn + skip cleanly zodat de OS-installer
# door kan gaan (packages staan al; daemon-runtime is optioneel — handmatige
# scans blijven mogelijk). Aansluiting op de gate in install-timers.sh.
enable_clamav_services() {
  if ws_is_dry_run; then
    local svc
    for svc in "$@"; do
      printf '  would run: systemctl enable --now %s\n' "$svc"
    done
    return 0
  fi
  if ! ws_systemd_available; then
    if ws_is_wsl; then
      ws_warn "WSL zonder actieve systemd — ClamAV daemons niet enable'd."
      ws_info "Daemon-runtime vereist [boot] systemd=true in /etc/wsl.conf + 'wsl --shutdown'."
    else
      ws_warn "systemd niet beschikbaar — ClamAV daemons niet enable'd."
    fi
    ws_skip "Service enable overgeslagen voor: $*"
    ws_info "Handmatige scans blijven werken via 'sudo bash common/scan.sh'."
    return 0
  fi

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
