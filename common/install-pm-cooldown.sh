#!/usr/bin/env bash
# Style-afwijking: shebang via `env bash` (niet `/bin/bash` zoals Google
# Shell Style aanbeveelt). Reden: repo target o.a. macOS, waar /bin/bash
# nog steeds 3.2 uit 2007 is (Apple update niet i.v.m. GPLv3). Met `env`
# wordt de homebrew bash 5.x gevonden. Rest van de baseline volgt Google.
# common/install-pm-cooldown.sh — installeer 7-daagse cooldown voor npm, pnpm
# en bun. Refuseert pakketversies gepubliceerd in de afgelopen N dagen — npm
# yankt malicious versies doorgaans binnen 24-48u, dus een 7-daagse quarantine
# vangt supply-chain attacks vóór ze jouw lockfile raken.
#
# Schrijft user-level config (geen sudo nodig):
#   ~/.npmrc        min-release-age=N            (npm 11.10+)
#                   minimum-release-age=N*1440   (pnpm 10.16+, in minuten)
#   ~/.bunfig.toml  [install] minimumReleaseAge=N*86400  (bun 1.3+, in seconden)
#
# Idempotent: re-run upsert de keys, dupliceert nooit. Bestaande auth tokens,
# registries en custom keys blijven staan. Bestandsmode wordt behouden
# (default 0600 voor nieuwe files, want kunnen tokens bevatten).
#
# Usage:
#   bash common/install-pm-cooldown.sh             # default 7 dagen
#   bash common/install-pm-cooldown.sh --days 14   # custom window
#   bash common/install-pm-cooldown.sh --check     # alleen huidige state tonen

set -euo pipefail

readonly NPMRC="${HOME}/.npmrc"
readonly BUNFIG="${HOME}/.bunfig.toml"

days=7
mode="install"

usage() {
  cat <<'EOF'
Usage: install-pm-cooldown.sh [--days N] [--check] [-h]

Installeert N-daagse package-manager cooldown voor npm, pnpm en bun.

Opties:
  --days N    Cooldown-venster in dagen (default 7, min 1).
  --check     Toon alleen huidige cooldown-staat, wijzig niets.
  -h, --help  Deze tekst.

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
      -h|--help) usage; exit 0 ;;
      *)
        echo "error: onbekend argument: $1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if ! [[ "$days" =~ ^[0-9]+$ ]] || (( days < 1 )); then
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
    ' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  write_preserving_mode "$file" "$tmp"
  rm -f "$tmp"
}

# Idempotente upsert van `minimumReleaseAge` binnen [install]-sectie in TOML.
# Maakt [install] aan als die ontbreekt.
upsert_bunfig() {
  local file="$1" age="$2"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v age="$age" '
      BEGIN { in_install = 0; written = 0 }
      /^[[:space:]]*\[install\][[:space:]]*$/ {
        print; in_install = 1; next
      }
      /^[[:space:]]*\[/ {
        if (in_install && !written) {
          print "minimumReleaseAge = " age
          written = 1
        }
        in_install = 0
        print; next
      }
      in_install && /^[[:space:]]*minimumReleaseAge[[:space:]]*=/ {
        print "minimumReleaseAge = " age
        written = 1
        next
      }
      { print }
      END {
        if (!written) {
          if (in_install) {
            print "minimumReleaseAge = " age
          } else {
            print ""
            print "[install]"
            print "minimumReleaseAge = " age
          }
        }
      }
    ' "$file" > "$tmp"
  else
    {
      printf '[install]\n'
      printf 'minimumReleaseAge = %s\n' "$age"
    } > "$tmp"
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
}

main() {
  parse_args "$@"

  if [[ "$mode" == "check" ]]; then
    check_only
    exit 0
  fi

  local npm_days="$days"
  local pnpm_minutes=$(( days * 24 * 60 ))
  local bun_seconds=$(( days * 24 * 60 * 60 ))

  echo "Installing ${days}-day package-manager cooldown..."

  upsert_kv "$NPMRC" "min-release-age" "$npm_days"
  upsert_kv "$NPMRC" "minimum-release-age" "$pnpm_minutes"
  echo "  ${NPMRC} : min-release-age=${npm_days} (npm), minimum-release-age=${pnpm_minutes} (pnpm)"

  upsert_bunfig "$BUNFIG" "$bun_seconds"
  echo "  ${BUNFIG} : [install] minimumReleaseAge=${bun_seconds} (bun)"

  cat <<'EOF'

Klaar. Cooldown is nu actief voor nieuwe installs.

Per-install override (alleen als je écht weet wat je doet — bv. urgent CVE-fix):
  - Zet in project-lokale .npmrc / bunfig.toml de waarde op 0
  - Raadpleeg de docs van je pkg-manager voor command-line overrides

Verificatie:
  bash common/install-pm-cooldown.sh --check
EOF
}

main "$@"
