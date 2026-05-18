#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# bootstrap.sh — detecteer OS via /etc/os-release en dispatch naar de juiste
# install.sh. Reduceert friction: gebruiker hoeft niet zelf te weten of 'ie
# alma/, arch/ of ubuntu/ moet aanroepen.
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash bootstrap.sh             # detecteert OS en dispatcht naar alma/arch/ubuntu install.sh
#   bash bootstrap.sh --dry-run        # toon welke sub-installer aangeroepen zou worden, geen wijzigingen
#   bash bootstrap.sh --version        # print versie en exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=common/lib.sh
source "${SCRIPT_DIR}/common/lib.sh"

# --version vóór de root-check zodat een gebruiker zonder sudo de versie kan
# opvragen. ws_handle_version exit 0 als de flag aanwezig is.
ws_handle_version "$@"

# --dry-run parsing — accepteer flag, propageer via WS_DRY_RUN env-var zodat
# sub-installers 'm ook zien (zie design.md D2). Geen andere argumenten verwacht.
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

# Root-check overslaan in dry-run: een gebruiker wil de dispatch-keuze ook
# zonder sudo kunnen voorspellen (CI / audit-evidence).
if ! ws_is_dry_run && [[ $EUID -ne 0 ]]; then
  echo "Run als root: sudo bash bootstrap.sh" >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "error: /etc/os-release niet leesbaar — kan OS niet detecteren." >&2
  echo "       Run handmatig: sudo bash alma/install.sh  (of arch/ of ubuntu/)" >&2
  exit 2
fi

# /etc/os-release is een veilig key=value bestand maintained door de distro.
# shellcheck source=/dev/null
source /etc/os-release

dispatch() {
  local sub="$1"
  local installer="${SCRIPT_DIR}/$sub/install.sh"
  # Toets alleen op bestaan — de installer wordt via `bash "$installer"`
  # aangeroepen en hoeft niet executable te zijn. De vorige check
  # ([[ ! -x && ! -f ]]) was tautologisch: een executable bestand is per
  # definitie ook een bestand, dus de -x-tak werd nooit hard gemaakt.
  if [[ ! -f "$installer" ]]; then
    echo "error: installer ontbreekt: $installer" >&2
    exit 2
  fi
  if ws_is_dry_run; then
    echo "Would dispatch to: $sub/install.sh"
    echo "(dry-run; no changes made)"
    return 0
  fi
  echo "==> ${PRETTY_NAME:-${ID:-onbekend}} → $sub/install.sh"
  bash "$installer"
}

case "${ID:-}" in
  almalinux | rocky | centos | rhel | fedora | ol)
    dispatch alma
    ;;
  arch | manjaro | endeavouros | artix)
    dispatch arch
    ;;
  ubuntu | debian | linuxmint | pop | elementary | raspbian)
    dispatch ubuntu
    ;;
  *)
    # Fallback via ID_LIKE.
    case "${ID_LIKE:-}" in
      *rhel* | *fedora* | *centos*)
        echo "  (ID=${ID:-?} onbekend, ID_LIKE=${ID_LIKE} → alma)"
        dispatch alma
        ;;
      *arch*)
        echo "  (ID=${ID:-?} onbekend, ID_LIKE=${ID_LIKE} → arch)"
        dispatch arch
        ;;
      *debian* | *ubuntu*)
        echo "  (ID=${ID:-?} onbekend, ID_LIKE=${ID_LIKE} → ubuntu)"
        dispatch ubuntu
        ;;
      *)
        echo "error: onbekend OS (ID=${ID:-?}, ID_LIKE=${ID_LIKE:-?})." >&2
        echo "       Run handmatig: sudo bash alma/install.sh  (of arch/ of ubuntu/)" >&2
        exit 2
        ;;
    esac
    ;;
esac
