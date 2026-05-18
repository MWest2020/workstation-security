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
#   sudo bash bootstrap.sh    # detecteert OS en dispatcht naar alma/arch/ubuntu install.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
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

dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

dispatch() {
  local sub="$1"
  local installer="$dir/$sub/install.sh"
  if [[ ! -x "$installer" && ! -f "$installer" ]]; then
    echo "error: installer ontbreekt: $installer" >&2
    exit 2
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
