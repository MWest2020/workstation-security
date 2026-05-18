#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: entrypoint           # one of: entrypoint | library | container-entrypoint | installer | tool
#
# <path>/<filename> — one-line description (wat doet dit script).
#
# Verdere uitleg in 1-3 alinea's: waarom bestaat dit script, welke probleem
# lost het op, welke design-keuzes zijn niet-vanzelfsprekend. Auditeur (of
# je toekomstige zelf) moet hier zien waaróm dingen zo zijn, niet alleen
# wát ze doen — dat lezen ze in de code zelf.
#
# Schrijft (verwijder als read-only):
#   /path/to/file        wat hier wordt aangepast en waarom
#   ~/.something         user-level state
#
# Idempotent: re-run is veilig. <Of: NIET idempotent — leg uit waarom dat
# bewust is.>
#
# Requires:
#   - gh (>= 2.0)
#   - jq
#   - python3
#   - secrets/.env (HYDRA_LABEL_PREFIX, optional)
#
# Style-afwijking: <documenteer hier elke deviation van Google Shell Style
# Guide, met reden. Bv. shebang via `env bash` voor macOS-compat.>
#
# Usage:
#   ./script.sh --foo bar                    # standaard
#   ./script.sh --foo bar --baz              # met optie
#   HYDRA_LABEL_PREFIX=wilco ./script.sh ... # met env-override
#
# Crontab (alleen invullen als role=entrypoint en applicable):
#   */10 * * * * /path/to/script.sh >> /path/to/log 2>&1
#
# Container CMD (alleen invullen als role=container-entrypoint):
#   CMD ["/entrypoint.sh"]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # template-skeleton; SCRIPT_DIR is used by consumer code
readonly SCRIPT_DIR

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# readonly constants — single place to tweak
readonly FOO_DEFAULT="bar"

# ---------------------------------------------------------------------------
# Library sources (if any)
# ---------------------------------------------------------------------------
# shellcheck source=lib/something.sh
# source "${SCRIPT_DIR}/lib/something.sh"

# Source secrets/.env if role=entrypoint and you need user-level config:
# REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# if [[ -f "${REPO_ROOT}/secrets/.env" ]]; then
#   set -a
#   # shellcheck disable=SC1091
#   . "${REPO_ROOT}/secrets/.env"
#   set +a
# fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local foo="${FOO_DEFAULT}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --foo)
        foo="$2"
        shift 2
        ;;
      -h | --help)
        # Print the header docblock as help text
        sed -n '2,40p' "$0" | sed 's/^# //;s/^#$//'
        exit 0
        ;;
      *) die "Onbekend argument: $1" ;;
    esac
  done

  log "running with foo=${foo}"
  # ... actual logic here ...
}

main "$@"
