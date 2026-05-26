#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: library
#
# common/lib.sh — gedeelde helpers en single source of truth voor de unit-set.
#
# Source dit bestand vanuit andere scripts; voer het niet zelfstandig uit. De
# library zet bewust GEEN shell-flags (`set -euo pipefail`): dat is aan de
# caller, zodat sourcing geen verrassend gedrag in de parent shell forceert.
#
# Bij toevoegen van een nieuwe timer of service: alleen hier de array
# uitbreiden. install-timers.sh, uninstall.sh en check.sh pakken het op.
# Style-afwijking: shebang via `env bash` i.p.v. `/bin/bash` voor macOS-bash-3.2
# portability en consistentie met de rest van het repo.

# Voorkom directe executie — dit is geen runnable script.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "error: common/lib.sh is een library — source hem, voer hem niet uit." >&2
  exit 2
fi

# Source-guard: voorkom dubbele inclusie als meerdere libraries elkaar inladen.
if [[ -n "${WS_LIB_SOURCED:-}" ]]; then
  return 0
fi
readonly WS_LIB_SOURCED=1

# Pad naar deze library — gebruikt door ws_version() om VERSION te lokaliseren
# relatief aan de repo-root, ongeacht waar de caller vandaan source't.
WS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WS_LIB_DIR

# --- status-iconen (repo-breed) ---
readonly WS_PASS="✓"
readonly WS_FAIL="✗"
readonly WS_WARN="!"
readonly WS_SKIP="-"

# --- timers/services geïnstalleerd door common/install-timers.sh ---
# Source of truth — heredocs in install-timers.sh moeten matchen op naam
# (smoke-test aan eind van install-timers.sh detecteert drift).
# shellcheck disable=SC2034  # gesourced extern (install-timers.sh, uninstall.sh, check.sh)
readonly WS_TIMERS=(
  "av-update.timer"
  "clamav-scan.timer"
  "rkhunter-check.timer"
)
# shellcheck disable=SC2034  # idem
readonly WS_SERVICES_GENERATED=(
  "av-update.service"
  "clamav-scan.service"
  "rkhunter-check.service"
)

# --- ClamAV scan-daemon kandidaten per OS (eerste actieve wint in check.sh) ---
# Alleen scan-daemons (clamd) — niet de freshclam signature-updater. Signature-
# updates draaien via av-update.timer; clamav-freshclam.service wordt door
# disable_freshclam_daemon expliciet uit gezet (zie common/install-base.sh).
# Alma ships clamd@scan; Arch/Ubuntu ships clamav-daemon.
# shellcheck disable=SC2034  # gesourced extern (check.sh)
readonly WS_CLAMAV_DAEMON_CANDIDATES=(
  "clamd@scan"
  "clamav-daemon"
)

# --- output helpers (alle status-messages indented voor leesbaar overzicht) ---
ws_ok() { printf '  %s %s\n' "$WS_PASS" "$*"; }
ws_fail() { printf '  %s %s\n' "$WS_FAIL" "$*" >&2; }
ws_warn() { printf '  %s %s\n' "$WS_WARN" "$*" >&2; }
ws_skip() { printf '  %s %s\n' "$WS_SKIP" "$*"; }
ws_info() { printf '  %s\n' "$*"; }

# --- dry-run ---
# Eén bron van waarheid voor dry-run-modus. Installers checken via
# ws_is_dry_run(); arg-parsing zet `WS_DRY_RUN=1` (en export't 'm) zodat de flag
# automatisch propageert naar sub-installers (zie design.md D2). Default 0.
ws_is_dry_run() {
  [[ "${WS_DRY_RUN:-0}" == "1" ]]
}

# ws_run_or_print: voer een commando uit, of print het in dry-run-modus zonder
# side effects. Werkt voor simpele exec-vorm (geen pipes/redirects); voor
# heredocs en redirects moet de caller zelf branchen op ws_is_dry_run.
# Output-prefix "  would run: " is consistent over installers heen voor copy-paste.
ws_run_or_print() {
  if ws_is_dry_run; then
    printf '  would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

# --- runtime detectors (WSL + systemd) ---
# WSL detecteert via /proc/sys/kernel/osrelease — bevat 'microsoft' (WSL1+2)
# of 'WSL' (WSL2-kernel-versie-suffix). Beide patterns gevangen.
ws_is_wsl() {
  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null
}

# --- versioning ---
# ws_version: print de inhoud van top-level VERSION-file (zonder trailing
# newline issue dankzij command-substitution-stripping in callers). Fallback
# 'unknown' wanneer de file ontbreekt of niet leesbaar is — zodat een script
# dat los gedownload werd niet faalt op een ontbrekend VERSION-bestand.
ws_version() {
  local version_file="${WS_LIB_DIR}/../VERSION"
  if [[ -r "$version_file" ]]; then
    cat "$version_file"
  else
    echo "unknown"
  fi
}

# ws_handle_version: scan "$@" voor --version of -V en exit 0 met een
# version-string als die aanwezig zijn. Aanroepen vóór andere arg-parsing zodat
# --version altijd voorrang heeft (ook gecombineerd met andere flags).
ws_handle_version() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --version | -V)
        echo "workstation-security $(ws_version)"
        exit 0
        ;;
    esac
  done
}

# Heeft systemd als init? Twee checks:
#   1. /run/systemd/system bestaat (alleen wanneer systemd booted heeft)
#   2. PID 1 is systemd (vs. wsl-init, sysvinit, etc.)
# WSL1: geen systemd. WSL2 standaard: geen systemd. WSL2 met
# /etc/wsl.conf [boot] systemd=true (+ wsl --shutdown): wél systemd.
ws_systemd_available() {
  [[ -d /run/systemd/system ]] && [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]
}
