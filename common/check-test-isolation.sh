#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# common/check-test-isolation.sh — draai een testsuite met een wegwerp-$HOME
# en faal als de suite daarin heeft geschreven.
#
# Werking: maak een lege map, draai het testcommando met HOME daarheen, en
# kijk wat erin beland is. Alles wat je vindt is een schrijfactie die anders
# in de echte $HOME van de gebruiker was gaan zitten. De cache-variabelen
# blijven naar de echte cache wijzen, zodat de toolchain niet elke run
# opnieuw alles ophaalt.
#
# Dit meet gedrag, niet intentie: een suite kan de check niet passeren door
# te beloven dat ze netjes is, alleen door het te zijn. En omdat de schrijf
# in de wegwerpmap landt, is de run zelf meteen ongevaarlijk.
#
# Writes: één tijdelijke map in $TMPDIR, die het zelf opruimt.
# Idempotent: ja — verandert niets aan de repo of aan de echte $HOME.
# Requires: bash, find, mktemp
#
# Usage:
#   bash common/check-test-isolation.sh uv run pytest -q
#   bash common/check-test-isolation.sh python -m pytest tests/
#   TEST_ISOLATION_ALLOW='.myapp/*' bash common/check-test-isolation.sh npm test
#
# Env:
#   TEST_ISOLATION_ALLOW  — padpatronen die genegeerd mogen worden, gescheiden
#                           door ':' (glob t.o.v. de wegwerp-$HOME).
#   TEST_ISOLATION_KEEP   — zet op 1 om de wegwerpmap te laten staan voor
#                           inspectie na een falende run.
#
# Exit:
#   0 — testcommando geslaagd én niets naar $HOME geschreven
#   1 — testcommando gefaald, of de suite schreef naar $HOME
#   2 — gebruiksfout
#
# Aanleiding: op 2026-08-15 bleek certswap's testsuite 28 tmp-deployments in
# de echte `~/.certswap/state.json` van de gebruiker te hebben geschreven —
# `apply` kent geen `--state`-vlag. Het commando `certswap upcoming` werd
# daardoor onleesbaar, kapotgemaakt door zijn eigen tests, en alle tests
# stonden al die tijd op groen.

set -euo pipefail

readonly REAL_HOME="$HOME"

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Filter treffers weg die de aanroeper expliciet heeft toegestaan.
is_allowed() {
  local path="$1" sandbox="$2" pattern
  [[ -z "${TEST_ISOLATION_ALLOW:-}" ]] && return 1
  local rel="${path#"${sandbox}"/}"
  local IFS=':'
  for pattern in ${TEST_ISOLATION_ALLOW}; do
    # shellcheck disable=SC2053  # glob-match is hier de bedoeling
    [[ "$rel" == $pattern ]] && return 0
  done
  return 1
}

# Draai het commando met een verlegde HOME. De caches blijven bewust op hun
# echte plek: een testrun hoort geen halve gigabyte opnieuw te downloaden om
# te bewijzen dat hij netjes is.
run_with_sandbox_home() {
  local sandbox="$1"
  shift
  HOME="$sandbox" \
    XDG_CACHE_HOME="${XDG_CACHE_HOME:-${REAL_HOME}/.cache}" \
    UV_CACHE_DIR="${UV_CACHE_DIR:-${REAL_HOME}/.cache/uv}" \
    PIP_CACHE_DIR="${PIP_CACHE_DIR:-${REAL_HOME}/.cache/pip}" \
    npm_config_cache="${npm_config_cache:-${REAL_HOME}/.npm}" \
    "$@"
}

report_offenders() {
  local -n found=$1
  echo "FOUT: de testsuite schreef ${#found[@]} pad(en) naar \$HOME:" >&2
  printf '  ~/%s\n' "${found[@]}" >&2
  echo >&2
  echo "Een test hoort binnen zijn eigen tmp-map te blijven. Maak het pad" >&2
  echo "env-tunable en wijs het in een autouse-fixture naar tmp_path; zie" >&2
  echo "certswap CERTSWAP_STATE voor het patroon. Is de schrijfactie hier" >&2
  echo "echt bedoeld, zet het pad dan in TEST_ISOLATION_ALLOW." >&2
}

main() {
  if [[ $# -eq 0 ]]; then
    echo "error: geef het testcommando als argumenten" >&2
    usage >&2
    exit 2
  fi
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  local sandbox
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/test-isolation-XXXXXX")"
  if [[ "${TEST_ISOLATION_KEEP:-0}" != "1" ]]; then
    # shellcheck disable=SC2064  # sandbox nu uitvouwen, niet bij exit
    trap "rm -rf '${sandbox}'" EXIT
  fi

  local rc=0
  run_with_sandbox_home "$sandbox" "$@" || rc=$?

  local -a offenders=()
  local path rel
  while IFS= read -r path; do
    rel="${path#"${sandbox}"/}"
    is_allowed "$path" "$sandbox" || offenders+=("$rel")
  done < <(find "$sandbox" -mindepth 1 \( -type f -o -type l \) -print 2>/dev/null || true)

  if [[ "${#offenders[@]}" -gt 0 ]]; then
    report_offenders offenders
    [[ "${TEST_ISOLATION_KEEP:-0}" == "1" ]] && echo "wegwerp-HOME: ${sandbox}" >&2
    exit 1
  fi

  if [[ "$rc" -ne 0 ]]; then
    echo "testcommando faalde (exit ${rc}); isolatie zelf was in orde" >&2
    exit 1
  fi

  echo "OK: testsuite schreef niets naar \$HOME"
}

main "$@"
