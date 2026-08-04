#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: entrypoint
#
# Style-afwijking: shebang via `env bash` voor consistentie met de repo — zie
# install-pm-cooldown.sh voor de reden.
#
# common/claude-pre-tool-use.sh — PreToolUse-hook voor Claude Code die
# secret-materiaal afschermt op shell-niveau.
#
# De denylist in ~/.claude/settings.json dekt de Read/Edit-tools. Die regels
# zeggen niets over wat een *commando* doet: `cat ~/.env` is een Bash-call en
# glipt er onderdoor. Deze hook sluit dat gat — hij krijgt elke tool-call vóór
# uitvoering binnen op stdin (JSON) en beslist.
#
# Twee tiers (zie het blok bij de patronen verderop), publiek materiaal blijft
# leesbaar, destructieve commando's zijn bewust buiten scope. Achtergrond:
# docs/explanation/claude-code-guardrails.md.
#
# Exit-codes (contract van Claude Code): 2 = harde blokkade, tool draait niet;
# 0 = toegestaan. Ontbreekt `jq`, dan blokkeert de hook — "kon niet verifiëren"
# mag nooit als "toegestaan" doorgaan.
#
# Writes: read-only (leest stdin, schrijft alleen meldingen naar stderr)
# Idempotent: ja (geen side effects)
# Requires: jq
#
# Usage:
#   # In ~/.claude/settings.json onder hooks.PreToolUse[].hooks[]:
#   #   {"type": "command", "command": "/pad/naar/common/claude-pre-tool-use.sh"}
#   echo '{"tool_name":"Bash","tool_input":{"command":"cat ~/.env"}}' \
#     | bash common/claude-pre-tool-use.sh    # exit 2, meldt de blokkade
#   bash common/claude-pre-tool-use.sh --self-test   # draait de fixtures, exit 0 als alles klopt
#   bash common/claude-pre-tool-use.sh --version     # print versie en exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# --- patronen ---------------------------------------------------------------
#
# Twee tiers, bewust verschillend streng:
#   Tier 1 — secret-bestanden (.env, *.key, *_rsa, *.p12, *.pfx): élke Bash-call
#            die ze noemt wordt geblokkeerd. Zulke paden hebben geen legitieme
#            reden om in een agent-commando voor te komen.
#   Tier 2 — credential-directories (~/.ssh, ~/.aws, ~/.gnupg, ~/.kube): alleen
#            geblokkeerd in combinatie met een lees-/kopieer-verb. Anders zou
#            `kubectl --kubeconfig ~/.kube/config get pods` sneuvelen, terwijl
#            dat precies het legitieme gebruik is: het proces leest zijn eigen
#            config, de inhoud belandt niet in de context van het model.
#
# Bewust NIET afgeschermd: *.pem (lezen mag — vaak een cert chain), *.crt en
# *.csr (publiek per definitie).
#
# Bewust buiten scope: destructieve commando's (git force-push, kubectl delete,
# terraform destroy). Dat is werkplek-beleid, geen security-baseline — wie dat
# wil, zet het in een tweede hook naast deze.

# Tier 1 in een commando-string. `.env` heeft geen stam (het bestand héét zo),
# dus dat patroon staat losser en accepteert een quote of spatie ervoor. De
# extensie-patronen eisen wél een stam (`server.key`), zodat een jq-filter als
# '.key' geen blokkade oplevert — dat is geen bestandspad.
readonly SECRET_CMD_RE='(^|[[:space:]=:"'"'"'(/])\.env(\.[A-Za-z0-9_-]+)?([[:space:]"'"'"'/]|$)|[A-Za-z0-9_~-]\.env(\.[A-Za-z0-9_-]+)?([[:space:]"'"'"'/]|$)|[A-Za-z0-9_~-]\.(key|p12|pfx)([[:space:]"'"'"'/]|$)|_rsa([[:space:]"'"'"'/]|$)'

# Template-varianten bevatten placeholders, geen secrets. Worden vóór de match
# uit de string geknipt zodat `cp .env.example .env` alleen op de echte .env slaat.
readonly TEMPLATE_RE='\.env[.-](example|sample|template)'

# Tier 2: credential-directories.
readonly CRED_DIR_RE='\.(ssh|aws|gnupg|kube)(/|[[:space:]"'"'"']|$)'

# Verbs die inhoud lezen, kopiëren of versturen. `ls` staat er bewust niet in:
# bestandsnamen zien is geen secret lezen.
# shellcheck disable=SC2016  # $ en ( zijn hier literals in een bracket-expressie
readonly READER_RE='(^|[;&|[:space:]$(])(cat|bat|less|more|head|tail|strings|xxd|od|base64|cut|awk|sed|grep|rg|jq|cp|scp|rsync|tar|zip|gzip|nc|curl|wget|openssl|gpg|source|\.)([[:space:]]|$)'

# Tier 1 als tool-pad (Read/Edit/Write). Anker op einde: hier is de hele string
# één pad, dus geen ruimte voor false positives.
readonly SECRET_PATH_RE='(^|/)\.env(\..+)?$|\.(key|p12|pfx)$|_rsa$|/\.(ssh|aws|gnupg|kube)(/|$)'

# Guard-files: de hook zelf en de allowlists eromheen. Een hek dat de agent kan
# verzetten is geen hek — een mens bewerkt deze met de hand, buiten Claude om.
readonly GUARD_RE='\.claude/hooks/|\.claude/[^/]*allowlist'
readonly WRITE_VERB_RE='>|\bsed\b|\btee\b|\bcp\b|\bmv\b|\brm\b|\bchmod\b|\bchattr\b|\bln\b|\bdd\b|\btruncate\b|\binstall\b'

# --- beslissing -------------------------------------------------------------

# block: meld de reden op stderr. De aanroeper bepaalt de exit-code, zodat de
# self-test dezelfde functie kan gebruiken zonder de shell te verlaten.
block() {
  printf 'BLOCKED: %s\n' "$1" >&2
}

# evaluate <tool> <command> <file_path> — return 2 bij blokkade, 0 bij toestaan.
# Alle regels staan in deze ene functie zodat de self-test exact hetzelfde pad
# doorloopt als een echte hook-invocatie.
evaluate() {
  local tool="$1" command="$2" file_path="$3"
  local scrubbed

  # 1. Guard-files — Claude mag zijn eigen hek niet verzetten.
  if [[ "$tool" == "Write" || "$tool" == "Edit" || "$tool" == "NotebookEdit" ]]; then
    if grep -qE "$GUARD_RE" <<<"$file_path"; then
      block "'${file_path}' is een guard-file — met de hand bewerken, nooit via de agent."
      return 2
    fi
  fi
  if [[ "$tool" == "Bash" ]] && grep -qE "$GUARD_RE" <<<"$command"; then
    if grep -qE "$WRITE_VERB_RE" <<<"$command"; then
      block "commando schrijft naar een guard-file — met de hand bewerken, nooit via de agent."
      return 2
    fi
  fi

  # 2. Tool-paden: secret lezen of bewerken via Read/Edit/Write/NotebookEdit.
  #    Dubbelop met de denylist in settings.json, en dat is de bedoeling: deze
  #    hook werkt ook op een machine waar die denylist ontbreekt of verminkt is.
  if [[ -n "$file_path" ]] && ! grep -qE "$TEMPLATE_RE" <<<"$file_path"; then
    if grep -qE "$SECRET_PATH_RE" <<<"$file_path"; then
      block "'${file_path}' is secret-materiaal — niet lezen of bewerken via de agent."
      return 2
    fi
  fi

  [[ "$tool" == "Bash" && -n "$command" ]] || return 0

  # Template-namen wegknippen vóór de match: `cp .env.example .env` moet op de
  # tweede treffen, niet op de eerste.
  scrubbed="$(sed -E "s/${TEMPLATE_RE}//g" <<<"$command")"

  # 3. Tier 1 — secret-bestand genoemd in een commando.
  if grep -qE "$SECRET_CMD_RE" <<<"$scrubbed"; then
    block "commando raakt secret-materiaal (.env / *.key / *_rsa / *.p12 / *.pfx). Voer het zelf uit als het echt nodig is."
    return 2
  fi

  # 4. Tier 2 — credential-directory in combinatie met een lees-verb.
  if grep -qE "$CRED_DIR_RE" <<<"$scrubbed" && grep -qE "$READER_RE" <<<"$scrubbed"; then
    block "commando leest uit een credential-store (~/.ssh, ~/.aws, ~/.gnupg, ~/.kube). Voer het zelf uit als het echt nodig is."
    return 2
  fi

  return 0
}

# --- self-test --------------------------------------------------------------

# Fixtures als 'verwacht|tool|command|file_path'. Beide richtingen staan erin:
# een hook die alles blokkeert is net zo stuk als een die niets blokkeert.
run_self_test() {
  local -a cases=(
    # moeten blokkeren
    "2|Bash|cat ~/.env|"
    "2|Bash|grep TOKEN app/.env.local|"
    "2|Bash|cat common/incident-token-revoke.env|"
    "2|Bash|cat /etc/ssl/server.key|"
    "2|Bash|cp ~/.ssh/id_ed25519 /tmp/x|"
    "2|Bash|base64 ~/.aws/credentials|"
    "2|Bash|cat ~/.kube/config|"
    "2|Bash|echo x > ~/.claude/hooks/pre-tool-use.sh|"
    "2|Read||/home/u/project/.env"
    "2|Edit||/home/u/.ssh/config"
    "2|Write||/etc/pki/tls/private/site.key"
    "2|Edit||/home/u/.claude/hooks/pre-tool-use.sh"
    # moeten doorgaan
    "0|Bash|kubectl --kubeconfig ~/.kube/config get pods|"
    "0|Bash|ls -la ~/.ssh|"
    "0|Bash|jq -r '.key' response.json|"
    "0|Bash|cat .env.example|"
    "0|Bash|openssl x509 -in cert.pem -noout -text|"
    "0|Bash|cat server.crt|"
    "0|Read||/home/u/project/cert.pem"
    "0|Write||/home/u/project/.env.example"
    "0|Read||/home/u/project/README.md"
  )

  local failed=0 line expected tool command file_path rc
  for line in "${cases[@]}"; do
    IFS='|' read -r expected tool command file_path <<<"$line"
    rc=0
    evaluate "$tool" "$command" "$file_path" 2>/dev/null || rc=$?
    if [[ "$rc" == "$expected" ]]; then
      ws_ok "${tool}: ${command:-$file_path}"
    else
      ws_fail "${tool}: ${command:-$file_path} — verwacht ${expected}, kreeg ${rc}"
      ((failed++)) || true
    fi
  done

  echo ""
  if ((failed == 0)); then
    echo "self-test: ${#cases[@]}/${#cases[@]} fixtures correct."
    return 0
  fi
  echo "self-test: ${failed} van ${#cases[@]} fixtures fout." >&2
  return 1
}

# --- main -------------------------------------------------------------------

main() {
  ws_handle_version "$@"

  if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit $?
  fi
  if [[ $# -gt 0 ]]; then
    echo "error: onbekend argument: $1" >&2
    exit 2
  fi

  if ! command -v jq &>/dev/null; then
    block "jq ontbreekt — de guardrail-hook kan de tool-call niet beoordelen."
    exit 2
  fi

  local input tool command file_path rc
  input="$(cat)"
  tool="$(jq -r '.tool_name // empty' <<<"$input")"
  command="$(jq -r '.tool_input.command // empty' <<<"$input")"
  file_path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"

  rc=0
  evaluate "$tool" "$command" "$file_path" || rc=$?
  exit "$rc"
}

main "$@"
