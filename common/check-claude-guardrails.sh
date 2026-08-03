#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# Style-afwijking: shebang via `env bash` (niet `/bin/bash`) voor consistentie
# met de rest van de repo — zie install-pm-cooldown.sh voor de reden.
#
# common/check-claude-guardrails.sh — verifieer de secret-guardrails in de
# Claude Code settings van de huidige user.
#
# Claude Code (en elke andere agent-CLI met een permissie-denylist) is een
# proces dat met jouw rechten je filesystem leest en schrijft. De denylist is
# de enige technische rem daarop; prozaregels in CLAUDE.md zijn beleid, geen
# handhaving. Dit script controleert of die rem daadwerkelijk aan staat.
#
# Twee soorten bevindingen:
#   1. Ontbrekende regel — een canonieke deny uit de rules-file staat niet in
#      de live settings. Secret-materiaal is dan niet afgeschermd.
#   2. Dode regel — een `Write(...)`-patroon in de denylist. Claude Code matcht
#      file-permissies alleen op `Edit(...)`; een Write-regel wordt genegeerd
#      en geeft dus schijnveiligheid. Dit is de reden dat dit script bestaat.
#
# Writes: read-only (leest settings + rules-file, schrijft niets)
# Idempotent: ja (read-only)
# Requires: jq, leesbare ~/.claude/settings.json
#
# Usage:
#   bash common/check-claude-guardrails.sh                          # audit huidige user
#   bash common/check-claude-guardrails.sh --settings /pad/naar.json  # andere settings-file
#   bash common/check-claude-guardrails.sh --rules /pad/regels.json   # eigen regelset
#   bash common/check-claude-guardrails.sh --version                  # print versie en exit
#
# Exit-codes: 0 = alles in orde, 1 = één probleem, 2 = twee of meer problemen,
# 2 = kan niet verifiëren (jq of settings-file ontbreekt). Capped op 2 zodat de
# code bruikbaar blijft in cron/CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

readonly DEFAULT_SETTINGS="${HOME}/.claude/settings.json"
readonly DEFAULT_RULES="${SCRIPT_DIR}/templates/claude-deny-secrets.json"

settings_file="$DEFAULT_SETTINGS"
rules_file="$DEFAULT_RULES"
errors=0
failures=()

# Registreer een probleem: print het, hou het vast voor de samenvatting en hoog
# de teller op. Zelfde pattern als check.sh zodat de output-vorm herkenbaar is.
record_fail() {
  ws_fail "$1"
  failures+=("$1")
  ((errors++)) || true
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --settings)
        [[ $# -ge 2 ]] || {
          echo "error: --settings vereist een pad" >&2
          exit 2
        }
        settings_file="$2"
        shift 2
        ;;
      --rules)
        [[ $# -ge 2 ]] || {
          echo "error: --rules vereist een pad" >&2
          exit 2
        }
        rules_file="$2"
        shift 2
        ;;
      *)
        echo "error: onbekend argument: $1" >&2
        exit 2
        ;;
    esac
  done
}

# Harde randvoorwaarden. Bewust exit 2 in plaats van een skip: "kon niet
# verifiëren" mag in een audit nooit als "in orde" gerapporteerd worden.
check_prerequisites() {
  if ! command -v jq &>/dev/null; then
    ws_fail "jq niet gevonden — kan settings niet verifiëren"
    exit 2
  fi
  if [[ ! -r "$settings_file" ]]; then
    ws_fail "settings niet leesbaar: ${settings_file}"
    exit 2
  fi
  if [[ ! -r "$rules_file" ]]; then
    ws_fail "regelset niet leesbaar: ${rules_file}"
    exit 2
  fi
  if ! jq empty "$settings_file" 2>/dev/null; then
    ws_fail "settings is geen valide JSON: ${settings_file}"
    exit 2
  fi
}

# Elke canonieke regel moet letterlijk in de live denylist staan. Letterlijke
# match, geen normalisatie: een glob die er "gelijkwaardig" uitziet kan in de
# praktijk anders matchen, en dat verschil is precies wat we willen zien.
check_required_rules() {
  local live_rules rule
  live_rules="$(jq -r '.permissions.deny // [] | .[]' "$settings_file")"

  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    if grep -qxF "$rule" <<<"$live_rules"; then
      ws_ok "$rule"
    else
      record_fail "ontbreekt: ${rule}"
    fi
  done < <(jq -r '.deny[]' "$rules_file")
}

# Dode Write(...)-regels opsporen. Bash(...)-regels met Write in de naam raken
# dit niet: we matchen alleen op het tool-prefix aan het begin van de string.
check_dead_write_rules() {
  local dead
  dead="$(jq -r '.permissions.deny // [] | .[] | select(startswith("Write("))' "$settings_file")"
  [[ -n "$dead" ]] || return 0

  local rule
  while IFS= read -r rule; do
    record_fail "dode regel (matcht niet): ${rule} — gebruik Edit(...) i.p.v. Write(...)"
  done <<<"$dead"
}

main() {
  ws_handle_version "$@"
  parse_args "$@"
  check_prerequisites

  echo ""
  echo "=== claude code guardrails ==="
  echo ""
  echo "Settings: ${settings_file}"
  echo "Regelset: ${rules_file}"
  echo ""
  echo "Secret-denies:"

  check_required_rules
  check_dead_write_rules

  echo ""
  if [[ $errors -eq 0 ]]; then
    echo "Alles in orde."
    exit 0
  fi

  echo "$errors probleem/problemen gevonden:"
  local f
  for f in "${failures[@]}"; do
    printf '  - %s\n' "$f"
  done
  exit $((errors > 2 ? 2 : errors))
}

main "$@"
