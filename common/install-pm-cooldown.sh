#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# Style-afwijking: shebang via `env bash` (niet `/bin/bash` zoals Google
# Shell Style aanbeveelt). Reden: repo target o.a. macOS, waar /bin/bash
# nog steeds 3.2 uit 2007 is (Apple update niet i.v.m. GPLv3). Met `env`
# wordt de homebrew bash 5.x gevonden. Rest van de baseline volgt Google.
#
# common/install-pm-cooldown.sh — installeer N-daagse cooldown voor npm, pnpm,
# bun, uv en pip. Refuseert pakketversies gepubliceerd in de afgelopen N dagen
# — registers yanken malicious versies doorgaans binnen 24-48u (npm) of een
# paar uur (PyPI), dus een 7-daagse quarantine vangt supply-chain attacks vóór
# ze jouw lockfile raken.
#
# Schrijft user-level config (geen sudo nodig):
#   ~/.npmrc                    min-release-age=N            (npm 11.10+)
#                               minimum-release-age=N*1440   (pnpm 10.16+, in minuten)
#   ~/.bunfig.toml              [install] minimumReleaseAge=N*86400  (bun 1.3+, in seconden)
#   ~/.config/uv/uv.toml        exclude-newer="N days"       (uv 0.9.17+)
#   ~/.config/pip/pip.conf      [install] uploaded-prior-to=PND  (pip 26.1+)
#
# Idempotent: re-run upsert de keys, dupliceert nooit. Bestaande auth tokens,
# registries en custom keys blijven staan. Bestandsmode wordt behouden
# (default 0600 voor nieuwe files, want kunnen tokens bevatten).
#
# Usage:
#   bash common/install-pm-cooldown.sh             # default 7 dagen
#   bash common/install-pm-cooldown.sh --days 14   # custom window
#   bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen
#   bash common/install-pm-cooldown.sh --dry-run   # print zou-toegepast-zijn wijzigingen, geen schrijven
#   bash common/install-pm-cooldown.sh --version   # print versie en exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

readonly NPMRC="${HOME}/.npmrc"
readonly BUNFIG="${HOME}/.bunfig.toml"
readonly UVTOML="${HOME}/.config/uv/uv.toml"
readonly PIPCONF="${HOME}/.config/pip/pip.conf"

days=7
mode="install"

usage() {
  cat <<'EOF'
Usage: install-pm-cooldown.sh [--days N] [--check] [--dry-run] [-h]

Installeert N-daagse package-manager cooldown voor npm, pnpm en bun.

Opties:
  --days N        Cooldown-venster in dagen (default 7, min 1).
  --check         Toon alleen huidige cooldown-staat, wijzig niets.
  --dry-run       Print de config-wijzigingen die zouden plaatsvinden, raak files niet aan.
  --version, -V   Print versie en exit.
  -h, --help      Deze tekst.

Files: ~/.npmrc en ~/.bunfig.toml (bestaande inhoud blijft behouden).
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)
        shift
        if [[ $# -eq 0 ]]; then
          echo "error: --days vereist een waarde" >&2
          exit 2
        fi
        days="$1"
        ;;
      --check) mode="check" ;;
      --dry-run) export WS_DRY_RUN=1 ;;
      --version | -V)
        echo "workstation-security $(ws_version)"
        exit 0
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "error: onbekend argument: $1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if ! [[ "$days" =~ ^[0-9]+$ ]] || ((days < 1)); then
    echo "error: --days moet positief geheel getal zijn (kreeg: $days)" >&2
    exit 2
  fi
}

# stat-mode wrapper — Linux én macOS.
file_mode() {
  local file="$1"
  stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "600"
}

# Atomair schrijven met behoud van mode. Default 0600 voor nieuwe files
# (npmrc/bunfig kunnen auth tokens bevatten — never widen).
write_preserving_mode() {
  local file="$1" content_file="$2"
  local target_mode="600"
  if [[ -f "$file" ]]; then
    target_mode="$(file_mode "$file")"
  fi
  install -m "$target_mode" "$content_file" "$file"
}

# Idempotente upsert van `key=value` in een ini-achtig bestand.
# Vervangt de eerste matchende regel, of voegt toe aan einde.
upsert_kv() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { seen = 0 }
      $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
        if (!seen) { printf "%s=%s\n", k, v; seen = 1 }
        next
      }
      { print }
      END { if (!seen) printf "%s=%s\n", k, v }
    ' "$file" >"$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >"$tmp"
  fi
  write_preserving_mode "$file" "$tmp"
  rm -f "$tmp"
}

# Idempotente upsert van `key = value` binnen een named section in een
# TOML/INI-achtig bestand. Maakt de section aan als die ontbreekt.
# Werkt zowel voor bunfig.toml ([install] minimumReleaseAge = N) als voor
# pip.conf ([install] uploaded-prior-to = PND).
upsert_section_kv() {
  local file="$1" section="$2" key="$3" value="$4"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v section="$section" -v k="$key" -v v="$value" '
      BEGIN { in_section = 0; written = 0 }
      $0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*$" {
        print; in_section = 1; next
      }
      /^[[:space:]]*\[/ {
        if (in_section && !written) {
          print k " = " v
          written = 1
        }
        in_section = 0
        print; next
      }
      in_section && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
        print k " = " v
        written = 1
        next
      }
      { print }
      END {
        if (!written) {
          if (in_section) {
            print k " = " v
          } else {
            print ""
            print "[" section "]"
            print k " = " v
          }
        }
      }
    ' "$file" >"$tmp"
  else
    {
      printf '[%s]\n' "$section"
      printf '%s = %s\n' "$key" "$value"
    } >"$tmp"
  fi
  write_preserving_mode "$file" "$tmp"
  rm -f "$tmp"
}

# Toon waarde van een specifieke key zonder andere inhoud te exposen.
# Greppt op key-prefix; printet geen andere regels (geen token-leak).
show_kv() {
  local file="$1" key="$2"
  if [[ ! -f "$file" ]]; then
    printf '  %-30s (file niet aanwezig)\n' "$file:$key"
    return
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -1 || true)"
  if [[ -n "$line" ]]; then
    printf '  %-30s %s\n' "$file:$key" "$line"
  else
    printf '  %-30s (not set)\n' "$file:$key"
  fi
}

check_only() {
  echo "Huidige cooldown-staat:"
  show_kv "$NPMRC" "min-release-age"
  show_kv "$NPMRC" "minimum-release-age"
  show_kv "$BUNFIG" "minimumReleaseAge"
  show_kv "$UVTOML" "exclude-newer"
  show_kv "$PIPCONF" "uploaded-prior-to"
}

main() {
  parse_args "$@"

  if [[ "$mode" == "check" ]]; then
    check_only
    exit 0
  fi

  local npm_days="$days"
  local pnpm_minutes=$((days * 24 * 60))
  local bun_seconds=$((days * 24 * 60 * 60))
  local python_iso="P${days}D"      # ISO 8601 duration — pip uploaded-prior-to
  local uv_friendly="${days} days"  # friendly relative duration — uv exclude-newer

  if ws_is_dry_run; then
    echo "Would install ${days}-day package-manager cooldown:"
    echo "  ${NPMRC}: would upsert min-release-age=${npm_days} (npm)"
    echo "  ${NPMRC}: would upsert minimum-release-age=${pnpm_minutes} (pnpm, minuten)"
    echo "  ${BUNFIG}: would upsert [install] minimumReleaseAge=${bun_seconds} (bun, seconden)"
    echo "  ${UVTOML}: would upsert exclude-newer=\"${uv_friendly}\" (uv)"
    echo "  ${PIPCONF}: would upsert [install] uploaded-prior-to=${python_iso} (pip)"
    echo ""
    echo "Huidige staat ter referentie:"
    check_only
    echo ""
    echo "(dry-run; no changes made)"
    exit 0
  fi

  echo "Installing ${days}-day package-manager cooldown..."

  upsert_kv "$NPMRC" "min-release-age" "$npm_days"
  upsert_kv "$NPMRC" "minimum-release-age" "$pnpm_minutes"
  echo "  ${NPMRC} : min-release-age=${npm_days} (npm), minimum-release-age=${pnpm_minutes} (pnpm)"

  upsert_section_kv "$BUNFIG" "install" "minimumReleaseAge" "$bun_seconds"
  echo "  ${BUNFIG} : [install] minimumReleaseAge=${bun_seconds} (bun)"

  # uv.toml leeft onder XDG_CONFIG_HOME; maak de dir aan als die nog niet bestaat.
  mkdir -p "$(dirname "$UVTOML")"
  upsert_kv "$UVTOML" "exclude-newer" "\"${uv_friendly}\""
  echo "  ${UVTOML} : exclude-newer=\"${uv_friendly}\" (uv)"

  # pip.conf leeft onder XDG_CONFIG_HOME; idem.
  mkdir -p "$(dirname "$PIPCONF")"
  upsert_section_kv "$PIPCONF" "install" "uploaded-prior-to" "$python_iso"
  echo "  ${PIPCONF} : [install] uploaded-prior-to=${python_iso} (pip)"

  cat <<'EOF'

Klaar. Cooldown is nu actief voor nieuwe installs (npm / pnpm / bun / uv / pip).

Per-install override (alleen als je écht weet wat je doet — bv. urgent CVE-fix):
  - Node-ecosysteem: zet in project-lokale .npmrc / bunfig.toml de waarde op 0
  - Python: pip install --uploaded-prior-to <past-date> ...
            uv add --exclude-newer 'never' ...   (of pin op een datum vóór nu)
  - Raadpleeg de docs van je pkg-manager voor command-line overrides

Verificatie:
  bash common/install-pm-cooldown.sh --check
EOF
}

main "$@"
