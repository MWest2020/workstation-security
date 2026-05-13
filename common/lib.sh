#!/usr/bin/env bash
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

# --- ClamAV-daemon kandidaten per OS (eerste actieve wint in check.sh) ---
# shellcheck disable=SC2034  # gesourced extern (check.sh)
readonly WS_CLAMAV_DAEMON_CANDIDATES=(
  "clamav-freshclam"
  "clamd@scan"
  "clamav-daemon"
)

# --- output helpers (alle status-messages indented voor leesbaar overzicht) ---
ws_ok()   { printf '  %s %s\n' "$WS_PASS" "$*"; }
ws_fail() { printf '  %s %s\n' "$WS_FAIL" "$*" >&2; }
ws_warn() { printf '  %s %s\n' "$WS_WARN" "$*" >&2; }
ws_skip() { printf '  %s %s\n' "$WS_SKIP" "$*"; }
ws_info() { printf '  %s\n' "$*"; }
