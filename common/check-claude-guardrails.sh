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
# Drie soorten bevindingen:
#   1. Ontbrekende regel — een canonieke deny uit de rules-file staat niet in
#      de live settings. Secret-materiaal is dan niet afgeschermd.
#   2. Dode regel — een `Write(...)`-patroon in de denylist. Claude Code matcht
#      file-permissies alleen op `Edit(...)`; een Write-regel wordt genegeerd
#      en geeft dus schijnveiligheid. Dit is de reden dat dit script bestaat.
#   3. Ontbrekende shell-laag — de denylist geldt voor de Read/Edit-tools, niet
#      voor `cat ~/.env` in een Bash-call. Daarvoor moet
#      common/claude-pre-tool-use.sh als PreToolUse-hook geregistreerd staan.
#
# Writes: read-only (leest settings + rules-file, schrijft niets)
# Idempotent: ja (read-only)
# Requires: jq, leesbare ~/.claude/settings.json
#
# Usage:
#   bash common/check-claude-guardrails.sh                          # audit huidige user
#   bash common/check-claude-guardrails.sh --settings /pad/naar.json  # andere settings-file
#   bash common/check-claude-guardrails.sh --rules /pad/regels.json   # eigen regelset
#   bash common/check-claude-guardrails.sh --self-test                # test de checker zelf tegen fixtures
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

# Idem voor condities die niet fout-maar-wel-te-adresseren zijn (b.v. een
# afwijkende hook-kopie). Rendert als `!`, telt wel mee in het totaal.
record_warn() {
  ws_warn "$1"
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

# jq is de enige harde eis van de self-test: die fabriceert zijn eigen settings
# en heeft dus geen live ~/.claude nodig.
require_jq() {
  if ! command -v jq &>/dev/null; then
    ws_fail "jq niet gevonden — kan settings niet verifiëren"
    exit 2
  fi
}

# Harde randvoorwaarden. Bewust exit 2 in plaats van een skip: "kon niet
# verifiëren" mag in een audit nooit als "in orde" gerapporteerd worden.
check_prerequisites() {
  require_jq
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

# De denylist dekt de Read/Edit-tools; shell-calls (`cat ~/.env`) glippen daar
# onderdoor. Dat gat wordt gedicht door common/claude-pre-tool-use.sh, maar
# alleen als die hook ook echt geregistreerd staat. Drie uitkomsten: niet
# geregistreerd (fout), geregistreerd maar een afwijkende kopie (waarschuwing —
# kan bewuste uitbreiding zijn), of geregistreerd en identiek.
check_hook_registration() {
  local repo_hook="${SCRIPT_DIR}/claude-pre-tool-use.sh"
  local registered hook_path
  registered="$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | .[]' "$settings_file")"

  if [[ -z "$registered" ]]; then
    record_fail "geen PreToolUse-hook geregistreerd — shell-calls naar secrets zijn niet afgeschermd"
    return 0
  fi

  hook_path="$(grep -F 'claude-pre-tool-use.sh' <<<"$registered" | head -1 || true)"
  if [[ -z "$hook_path" ]]; then
    record_fail "PreToolUse-hook(s) geregistreerd, maar niet common/claude-pre-tool-use.sh — shell-calls naar secrets zijn niet afgeschermd"
    return 0
  fi

  if [[ ! -r "$hook_path" ]]; then
    record_fail "geregistreerde hook niet leesbaar: ${hook_path}"
    return 0
  fi

  if ! cmp -s "$hook_path" "$repo_hook"; then
    record_warn "geregistreerde hook wijkt af van de repo-versie: ${hook_path}"
    return 0
  fi

  ws_ok "PreToolUse-hook actief en identiek aan repo-versie"
}

# --- self-test --------------------------------------------------------------

# Black-box: elke case draait dit script opnieuw tegen een gefabriceerde
# settings-file en toetst exit-code én melding. Fixtures worden afgeleid van de
# echte regelset, zodat de test meebeweegt als die lijst verandert — een test
# met een eigen kopie van de regels test alleen zichzelf.
#
# De 'alles in orde'-case staat er bewust bij: een checker die overal een
# probleem ziet is net zo waardeloos als een die nooit iets ziet.
run_self_test() {
  local tmp repo_hook failed=0
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064  # $tmp nu expanderen, niet bij trap-executie
  trap "rm -rf '${tmp}'" EXIT
  repo_hook="${SCRIPT_DIR}/claude-pre-tool-use.sh"

  # Basis: alle canonieke regels aanwezig, hook geregistreerd op het repo-pad.
  jq --arg hook "$repo_hook" \
    '{permissions: {deny: .deny}, hooks: {PreToolUse: [{matcher: "", hooks: [{type: "command", command: $hook}]}]}}' \
    "$rules_file" >"${tmp}/ok.json"

  jq 'del(.permissions.deny[0])' "${tmp}/ok.json" >"${tmp}/missing-rule.json"
  jq '.permissions.deny += ["Write(**/.env)"]' "${tmp}/ok.json" >"${tmp}/dead-write.json"
  jq 'del(.hooks)' "${tmp}/ok.json" >"${tmp}/no-hook.json"
  jq '.hooks.PreToolUse[0].hooks[0].command = "/bin/true"' "${tmp}/ok.json" >"${tmp}/other-hook.json"
  printf 'dit is geen json\n' >"${tmp}/broken.json"

  assert_case() {
    local name="$1" settings="$2" want_rc="$3" want_text="$4"
    local out rc=0
    out="$(bash "${BASH_SOURCE[0]}" --settings "$settings" 2>&1)" || rc=$?
    if [[ "$rc" == "$want_rc" ]] && grep -qF "$want_text" <<<"$out"; then
      ws_ok "$name"
      return 0
    fi
    ws_fail "${name} — verwacht exit ${want_rc} + '${want_text}', kreeg exit ${rc}"
    ((failed++)) || true
  }

  assert_case "volledige settings" "${tmp}/ok.json" 0 "Alles in orde"
  assert_case "ontbrekende regel" "${tmp}/missing-rule.json" 1 "ontbreekt:"
  assert_case "dode Write-regel" "${tmp}/dead-write.json" 1 "dode regel"
  assert_case "geen hook geregistreerd" "${tmp}/no-hook.json" 1 "geen PreToolUse-hook"
  assert_case "andere hook geregistreerd" "${tmp}/other-hook.json" 1 "niet common/claude-pre-tool-use.sh"
  assert_case "kapotte settings" "${tmp}/broken.json" 2 "geen valide JSON"
  assert_case "settings ontbreekt" "${tmp}/bestaat-niet.json" 2 "niet leesbaar"

  echo ""
  if ((failed == 0)); then
    echo "self-test: 7/7 fixtures correct."
    return 0
  fi
  echo "self-test: ${failed} van 7 fixtures fout." >&2
  return 1
}

main() {
  ws_handle_version "$@"

  if [[ "${1:-}" == "--self-test" ]]; then
    require_jq
    echo ""
    echo "=== check-claude-guardrails self-test ==="
    echo ""
    run_self_test
    exit $?
  fi
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
  echo "Shell-laag:"
  check_hook_registration

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
