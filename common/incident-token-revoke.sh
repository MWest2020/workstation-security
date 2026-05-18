#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# Style-afwijkingen t.o.v. Google Shell Style baseline (zie ~/.claude/CLAUDE.md):
#   1. Shebang via `env bash` i.p.v. `/bin/bash` — repo target o.a. macOS,
#      waar /bin/bash nog 3.2 uit 2007 is. `env` vindt de homebrew bash 5.x.
#   2. `set -e` is bewust UIT (zie comment bij `set -uo pipefail` hieronder).
# common/incident-token-revoke.sh — IR voor CanisterSprawl-klasse GitHub-token
# dead-man's switch (carlini 2026-05-12: gh-token-monitor variant).
#
# Flow: capture-token-hash → detect → SIGKILL-first → disarm → invalidate
# locaal → manual web revoke → verify via gevangen token.
#
# Footprint-bewust: incident-dir wordt LAZY aangemaakt in /tmp/incident-<ts>/
# (alleen als er artefacten zijn), evidence per file gecapped op 1 MiB, schone
# runs laten niks achter. Geen separaat Markdown-dossier — de log file IS het
# verslag, en wordt optioneel gemaild (zie incident-token-revoke.env.example).
#
# Usage:
#   bash incident-token-revoke.sh                    # interactief
#   bash incident-token-revoke.sh --dry-run          # alleen detectie
#   bash incident-token-revoke.sh --yes-neutralize   # confirm-skip op stap 2
#   bash incident-token-revoke.sh --mail-env <path>  # alt path naar mail.env
#
# Exit codes:
#   0  - schoon, niets gevonden (revoke eventueel handmatig afgerond)
#   1  - artefacten gevonden, geneutraliseerd, token-revoke geverifieerd
#   2  - fout: detectie/neutralisatie/verificatie faalde
#   10 - gebruiker afgebroken

# `set -e` is hier bewust UIT. Reden: een IR-script doet veel "speculatieve"
# acties (pkill -9 op niet-bestaand proces, systemctl stop op niet-aanwezige
# unit, grep -q dat geen treffer vindt) die allemaal exit-code != 0 geven op
# een schone machine. Met -e zou het script daar exit'en en de revoke-URL,
# verify en mail-stappen overslaan — precies in een incident niet wat je wil.
# Failures worden expliciet afgehandeld per commando (`|| true` waar het
# verwacht is, of return-check waar het ertoe doet).
set -uo pipefail

readonly SCRIPT_NAME="incident-token-revoke"
readonly SCRIPT_VERSION="0.1.0"
readonly TOKENS_URL="https://github.com/settings/tokens"
readonly MAX_EVIDENCE_BYTES=1048576   # 1 MiB cap per evidence-file

INCIDENT_TS="$(date -u +%Y%m%dT%H%M%SZ)"
readonly INCIDENT_TS
readonly INCIDENT_DIR="/tmp/incident-${INCIDENT_TS}"
# INCIDENT_DIR wordt LAZY aangemaakt — alleen bij eerste finding/log-flush.
INCIDENT_DIR_CREATED=0
LOG_FILE=""

# Bekende IOCs (CanisterSprawl variant)
readonly DEADMAN_SCRIPT="$HOME/.local/bin/gh-token-monitor.sh"
readonly LINUX_UNIT_NAME="gh-token-monitor.service"
readonly LINUX_UNIT_PATH="$HOME/.config/systemd/user/${LINUX_UNIT_NAME}"
readonly MACOS_LABEL="com.user.gh-token-monitor"
readonly MACOS_PLIST="$HOME/Library/LaunchAgents/${MACOS_LABEL}.plist"

readonly EXTRA_LINUX_PATHS=(
  "$HOME/.config/autostart/gh-token-monitor.desktop"
  "$HOME/.bashrc.d/gh-token-monitor"
)
readonly EXTRA_MACOS_PATHS=(
  "$HOME/Library/LaunchDaemons/${MACOS_LABEL}.plist"
)

# Heuristische scan (carlini: "bunch of persistence mechanisms")
readonly HEURISTIC_DIRS=(
  "$HOME/.config/systemd/user"
  "$HOME/.local/bin"
  "$HOME/.config/autostart"
  "$HOME/.bashrc.d"
)
# shellcheck disable=SC2016  # bewust single-quote: grept naar de literal $HOME-string in payload-scripts
readonly HEURISTIC_PATTERN='api\.github\.com/user|gh-token-monitor|rm[[:space:]]+-rf[[:space:]]+(\$HOME|~)'

case "$(uname -s)" in
  Linux*)  OS="linux" ;;
  Darwin*) OS="macos" ;;
  *) echo "FATAL: unsupported OS: $(uname -s)" >&2; exit 2 ;;
esac

# ---------- argumenten ----------

DRY_RUN=0
AUTO_YES_NEUTRALIZE=0
MAIL_ENV_FILE="${INCIDENT_MAIL_ENV:-$HOME/.config/workstation-security/mail.env}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes-neutralize) AUTO_YES_NEUTRALIZE=1 ;;
    --mail-env)
      shift
      [[ $# -gt 0 ]] || { echo "--mail-env vereist een pad" >&2; exit 2; }
      MAIL_ENV_FILE="$1"
      ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--dry-run] [--yes-neutralize] [--mail-env <path>] [-h]

Detect + disarm CanisterSprawl-klasse GitHub-token dead-man's switch,
walk daarna door manual revoke + verify.

Opties:
  --dry-run            Alleen detectie, geen wijzigingen.
  --yes-neutralize     Skip confirm op stap 2 (NIET op de revoke-bevestiging).
  --mail-env <path>    Pad naar mail env-file (default: \$INCIDENT_MAIL_ENV
                       of ~/.config/workstation-security/mail.env).

Evidence + log gaan naar /tmp/incident-<ts>/ — alleen als er findings zijn.
Schone runs laten niks op disk achter.
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ---------- helpers ----------

ensure_incident_dir() {
  if [[ $INCIDENT_DIR_CREATED -eq 0 ]]; then
    mkdir -p "$INCIDENT_DIR" && chmod 0700 "$INCIDENT_DIR"
    LOG_FILE="${INCIDENT_DIR}/incident.log"
    : > "$LOG_FILE"
    INCIDENT_DIR_CREATED=1
  fi
}

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line
  line="$(printf '[%s] [%s] %s' "$ts" "$level" "$msg")"
  printf '%s\n' "$line"
  if [[ "$level" == "WARN" || "$level" == "ERROR" ]]; then
    ensure_incident_dir
  fi
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

confirm() {
  local prompt="$1"
  local auto="${2:-0}"
  if [[ "$auto" -eq 1 ]]; then
    log INFO "auto-confirm: $prompt"
    return 0
  fi
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

archive() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  ensure_incident_dir
  local base dest
  base="$(basename "$src")"
  dest="${INCIDENT_DIR}/evidence-${base}-$(date -u +%s)"
  # Cap op MAX_EVIDENCE_BYTES — payloads zijn klein, maar bescherming tegen
  # symlink naar /dev/urandom of een opzettelijk opgeblazen artefact.
  if [[ -f "$src" ]]; then
    head -c "$MAX_EVIDENCE_BYTES" "$src" > "$dest" 2>/dev/null || true
    local actual
    actual="$(stat -c '%s' "$src" 2>/dev/null || stat -f '%z' "$src" 2>/dev/null || echo 0)"
    if [[ "$actual" -gt "$MAX_EVIDENCE_BYTES" ]]; then
      log WARN "archived (truncated to ${MAX_EVIDENCE_BYTES} bytes): $src -> $dest"
    else
      log INFO "archived: $src -> $dest"
    fi
  else
    # niet-regular file (dir, symlink) — sla metadata op, geen recursive copy
    ls -ld "$src" > "$dest" 2>/dev/null || true
    log INFO "archived metadata: $src -> $dest"
  fi
}

# ---------- stap 0: capture token vóór we wat aanraken ----------

STOLEN_TOKEN=""
STOLEN_HASH=""
STOLEN_LAST4=""

capture_token() {
  if ! command -v gh >/dev/null 2>&1; then
    log INFO "gh CLI niet aanwezig — geen token-capture"
    return 0
  fi
  STOLEN_TOKEN="$(gh auth token 2>/dev/null || true)"
  if [[ -z "$STOLEN_TOKEN" ]]; then
    log INFO "geen actieve gh-token op deze machine"
    return 0
  fi
  STOLEN_LAST4="${STOLEN_TOKEN: -4}"
  STOLEN_HASH="$(printf '%s' "$STOLEN_TOKEN" | sha256sum | cut -d' ' -f1)"
  log INFO "gh-token gevangen: last4=${STOLEN_LAST4} sha256=${STOLEN_HASH:0:16}…"
}

# ---------- stap 1: detectie ----------

DEADMAN_FOUND=0
FOUND_ARTIFACTS=()

flag_artifact() {
  local kind="$1" path="$2"
  FOUND_ARTIFACTS+=("$kind:$path")
  DEADMAN_FOUND=1
  log WARN "found $kind: $path"
}

detect_common() {
  [[ -f "$DEADMAN_SCRIPT" ]] && flag_artifact "deadman-script" "$DEADMAN_SCRIPT"
}

detect_linux() {
  log INFO "scanning Linux user-persistence"
  [[ -f "$LINUX_UNIT_PATH" ]] && flag_artifact "systemd-unit" "$LINUX_UNIT_PATH"
  if command -v systemctl >/dev/null 2>&1; then
    # Capture eerst, dan grep tegen here-string — voorkomt dat `grep -q` early-
    # exit'et en systemctl/awk een SIGPIPE-induced non-zero geven. In een IR-
    # context is een silent-miss op een actieve unit veel erger dan een
    # over-flag, dus we accepteren een potentieel match in beschrijving-velden.
    local units_listing
    units_listing="$(systemctl --user list-units --all --no-legend 2>/dev/null)"
    if grep -qi 'gh-token-monitor' <<<"$units_listing"; then
      flag_artifact "systemd-active" "$LINUX_UNIT_NAME"
    fi
  fi
  for p in "${EXTRA_LINUX_PATHS[@]}"; do
    [[ -e "$p" ]] && flag_artifact "extra-file" "$p"
  done
}

detect_macos() {
  log INFO "scanning macOS persistence"
  [[ -f "$MACOS_PLIST" ]] && flag_artifact "launchagent-plist" "$MACOS_PLIST"
  if command -v launchctl >/dev/null 2>&1; then
    # Capture eerst (zie commentaar in detect_linux voor reden). awk slaat
    # alleen de Label-kolom uit, grep -x doet de exact-match check.
    local launchctl_listing labels
    launchctl_listing="$(launchctl list 2>/dev/null)"
    labels="$(awk '{print $3}' <<<"$launchctl_listing")"
    if grep -qx "$MACOS_LABEL" <<<"$labels"; then
      flag_artifact "launchagent-active" "$MACOS_LABEL"
    fi
  fi
  for p in "${EXTRA_MACOS_PATHS[@]}"; do
    [[ -e "$p" ]] && flag_artifact "extra-file" "$p"
  done
}

detect_heuristic() {
  log INFO "heuristic grep across user-persistence dirs"
  local d hit
  for d in "${HEURISTIC_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && flag_artifact "heuristic" "$hit"
    done < <(grep -rlE "$HEURISTIC_PATTERN" "$d" 2>/dev/null || true)
  done
}

detect_processes() {
  log INFO "scanning for stray gh-token-monitor processes"
  command -v pgrep >/dev/null 2>&1 || return 0
  local pids
  pids="$(pgrep -fa 'gh-token-monitor|token-monitor' 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && flag_artifact "process" "$line"
    done <<< "$pids"
  fi
}

# ---------- stap 2: neutralisatie ----------

neutralize_processes_first() {
  # SIGKILL eerst — voorkomt SIGTERM-trap die alsnog rm -rf ~/ kan triggeren.
  log INFO "SIGKILL processen voor we systemd/launchd betrekken"
  if command -v pkill >/dev/null 2>&1; then
    pkill -9 -f 'gh-token-monitor' 2>/dev/null || true
    pkill -9 -f 'token-monitor' 2>/dev/null || true
  fi
  if [[ "$OS" == "linux" ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user kill --signal=SIGKILL "$LINUX_UNIT_NAME" 2>/dev/null || true
  fi
  if [[ "$OS" == "macos" ]] && command -v launchctl >/dev/null 2>&1; then
    local uid; uid="$(id -u)"
    launchctl kill SIGKILL "gui/${uid}/${MACOS_LABEL}" 2>/dev/null || true
  fi
  sleep 1
}

neutralize_linux() {
  log INFO "ontwapenen Linux artefacten"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "$LINUX_UNIT_NAME" 2>/dev/null || true
    systemctl --user disable "$LINUX_UNIT_NAME" 2>/dev/null || true
  fi
  if [[ -f "$LINUX_UNIT_PATH" ]]; then
    archive "$LINUX_UNIT_PATH"
    rm -f "$LINUX_UNIT_PATH" && log INFO "removed: $LINUX_UNIT_PATH"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  for p in "${EXTRA_LINUX_PATHS[@]}"; do
    [[ -e "$p" ]] || continue
    archive "$p"
    rm -rf "$p" && log INFO "removed: $p"
  done
}

neutralize_macos() {
  log INFO "ontwapenen macOS artefacten"
  if command -v launchctl >/dev/null 2>&1; then
    local uid; uid="$(id -u)"
    launchctl bootout "gui/${uid}/${MACOS_LABEL}" 2>/dev/null \
      || launchctl unload -w "$MACOS_PLIST" 2>/dev/null \
      || true
  fi
  if [[ -f "$MACOS_PLIST" ]]; then
    archive "$MACOS_PLIST"
    rm -f "$MACOS_PLIST" && log INFO "removed: $MACOS_PLIST"
  fi
  for p in "${EXTRA_MACOS_PATHS[@]}"; do
    [[ -e "$p" ]] || continue
    archive "$p"
    rm -f "$p" && log INFO "removed: $p"
  done
}

neutralize_common() {
  if [[ -f "$DEADMAN_SCRIPT" ]]; then
    archive "$DEADMAN_SCRIPT"
    rm -f "$DEADMAN_SCRIPT" && log INFO "removed: $DEADMAN_SCRIPT"
  fi
  # Heuristische treffers: alleen evidence, geen auto-remove.
  # Reden: false-positive op een legit script zou data weggooien.
  local entry f
  for entry in "${FOUND_ARTIFACTS[@]}"; do
    if [[ "$entry" == heuristic:* ]]; then
      f="${entry#heuristic:}"
      archive "$f"
      log WARN "heuristic hit, NOT auto-removed: $f"
    fi
  done
}

# ---------- stap 3: lokaal onbruikbaar maken ----------

local_invalidate() {
  log INFO "gh auth logout + keychain cleanup"

  if command -v gh >/dev/null 2>&1; then
    gh auth logout --hostname github.com 2>&1 \
      | (while IFS= read -r l; do log INFO "gh: $l"; done) || true
  fi

  if command -v secret-tool >/dev/null 2>&1; then
    secret-tool clear service gh:github.com 2>/dev/null || true
    secret-tool clear protocol https server github.com 2>/dev/null || true
  fi

  if [[ "$OS" == "macos" ]] && command -v security >/dev/null 2>&1; then
    security delete-generic-password -s "gh:github.com" 2>/dev/null || true
    security delete-internet-password -s "github.com" 2>/dev/null || true
  fi

  # Env + rc scan — alleen WARN, geen auto-edit (operator beslist).
  if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_ENTERPRISE_TOKEN:-}" ]]; then
    log WARN "GH_TOKEN/GITHUB_TOKEN/GH_ENTERPRISE_TOKEN aanwezig in env — 'unset' in deze shell"
  fi
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
            "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.netrc"; do
    [[ -f "$rc" ]] || continue
    if grep -qE 'GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN|github\.com.+password' "$rc" 2>/dev/null; then
      log WARN "token-referentie in $rc — handmatig opschonen"
    fi
  done
  if [[ -f "$HOME/.config/gh/hosts.yml" ]]; then
    if grep -q 'oauth_token:' "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
      log WARN "$HOME/.config/gh/hosts.yml bevat nog oauth_token: — handmatig wissen"
    fi
  fi
}

# ---------- stap 4: revoke URL ----------

print_revoke_url() {
  cat <<EOF

  Open je browser nu naar:
      $TOKENS_URL

  - Klik "Delete" / "Revoke" voor de relevante token(s).
  - GitHub heeft géén user-self-revoke REST endpoint voor PATs.
    Dit is en blijft een bewuste handmatige handeling.

EOF
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$TOKENS_URL" | wl-copy 2>/dev/null && log INFO "URL → clipboard (wl-copy)"
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$TOKENS_URL" | xclip -selection clipboard 2>/dev/null && log INFO "URL → clipboard (xclip)"
  elif command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$TOKENS_URL" | pbcopy 2>/dev/null && log INFO "URL → clipboard (pbcopy)"
  fi
}

# ---------- stap 5: verify ----------

verify_revoke() {
  if [[ -z "$STOLEN_TOKEN" ]]; then
    log WARN "geen gevangen token om te verifiëren — verify overgeslagen"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    log WARN "curl ontbreekt — kan revoke niet verifiëren"
    return 0
  fi
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $STOLEN_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user 2>/dev/null)"
  log INFO "api.github.com/user → HTTP $code (verwacht 401)"
  [[ "$code" == "401" ]]
}

# ---------- mail (optioneel) ----------

send_mail_if_configured() {
  if [[ ! -f "$MAIL_ENV_FILE" ]]; then
    return 0
  fi
  local perm
  perm="$(stat -c '%a' "$MAIL_ENV_FILE" 2>/dev/null \
        || stat -f '%Lp' "$MAIL_ENV_FILE" 2>/dev/null || echo "")"
  case "$perm" in
    600|400) ;;
    *) log WARN "$MAIL_ENV_FILE mode=$perm (vereist 600/400) — mail overgeslagen"; return 0 ;;
  esac
  # shellcheck disable=SC1090
  source "$MAIL_ENV_FILE"
  local var
  for var in MAIL_SMTP_HOST MAIL_SMTP_PORT MAIL_FROM MAIL_TO MAIL_USER MAIL_APP_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
      log WARN "$var ontbreekt in $MAIL_ENV_FILE — mail overgeslagen"
      return 0
    fi
  done
  if ! command -v curl >/dev/null 2>&1; then
    log WARN "curl ontbreekt — mail overgeslagen"
    return 0
  fi

  local body
  body="$(mktemp)"
  {
    printf 'From: "%s" <%s>\r\n' "${MAIL_FROM_NAME:-Workstation IR}" "$MAIL_FROM"
    printf 'To: %s\r\n' "$MAIL_TO"
    printf 'Subject: [WS-SEC] incident-token-revoke %s %s (%d artefacten)\r\n' \
      "$(hostname)" "$INCIDENT_TS" "${#FOUND_ARTIFACTS[@]}"
    printf 'Date: %s\r\n' "$(date -R)"
    printf 'Content-Type: text/plain; charset=UTF-8\r\n'
    printf '\r\n'
    printf 'Workstation: %s\r\nTimestamp:   %s\r\nEvidence:    %s\r\nArtefacten:  %d\r\nToken hash:  %s\r\nToken last4: %s\r\n' \
      "$(hostname)" "$INCIDENT_TS" "$INCIDENT_DIR" \
      "${#FOUND_ARTIFACTS[@]}" "${STOLEN_HASH:-(none)}" "${STOLEN_LAST4:-(none)}"
    printf '\r\n--- log (tail 100) ---\r\n'
    [[ -f "$LOG_FILE" ]] && tail -n 100 "$LOG_FILE"
  } > "$body"

  curl --silent --ssl-reqd \
    --url "smtps://${MAIL_SMTP_HOST}:${MAIL_SMTP_PORT}" \
    --user "${MAIL_USER}:${MAIL_APP_PASSWORD}" \
    --mail-from "$MAIL_FROM" \
    --mail-rcpt "$MAIL_TO" \
    --upload-file "$body"
  local rc=$?
  rm -f "$body"
  if [[ $rc -eq 0 ]]; then
    log INFO "mail verzonden → $MAIL_TO via $MAIL_SMTP_HOST"
  else
    log ERROR "mail-verzending faalde (curl rc=$rc)"
  fi
}

# ---------- cleanup ----------

cleanup_if_clean_run() {
  # Verwijder lege incident-dir bij schone exit — geen disk-pollutie in /tmp.
  if [[ $INCIDENT_DIR_CREATED -eq 1 ]] && [[ $DEADMAN_FOUND -eq 0 ]]; then
    rm -rf "$INCIDENT_DIR" 2>/dev/null || true
  fi
}

# ---------- main ----------

main() {
  log INFO "=== ${SCRIPT_NAME} v${SCRIPT_VERSION} on ${OS} ==="
  log INFO "dry-run=$DRY_RUN auto-yes-neutralize=$AUTO_YES_NEUTRALIZE"
  log INFO "mail-env (optioneel): $MAIL_ENV_FILE"

  log INFO "--- stap 0: capture gh-token (hash + last4) ---"
  capture_token

  log INFO "--- stap 1: detect ---"
  detect_common
  case "$OS" in
    linux) detect_linux ;;
    macos) detect_macos ;;
  esac
  detect_heuristic
  detect_processes

  if [[ $DEADMAN_FOUND -eq 0 ]]; then
    log INFO "geen bekende dead-man artefacten gevonden"
  else
    log WARN "${#FOUND_ARTIFACTS[@]} verdacht(e) artefact(en):"
    for a in "${FOUND_ARTIFACTS[@]}"; do log WARN "  - $a"; done
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "dry-run — gestopt na detectie"
    cleanup_if_clean_run
    [[ $DEADMAN_FOUND -eq 1 ]] && exit 1 || exit 0
  fi

  if [[ $DEADMAN_FOUND -eq 1 ]]; then
    log INFO "--- stap 2: neutralize (SIGKILL-first) ---"
    if ! confirm "Doorgaan met neutralisatie (SIGKILL + archive + remove)?" "$AUTO_YES_NEUTRALIZE"; then
      log INFO "afgebroken vóór neutralisatie"
      exit 10
    fi
    neutralize_processes_first
    neutralize_common
    case "$OS" in
      linux) neutralize_linux ;;
      macos) neutralize_macos ;;
    esac
    log INFO "neutralisatie klaar"
  else
    log INFO "--- stap 2: overgeslagen (niets te ontwapenen) ---"
  fi

  log INFO "--- stap 3: lokaal onbruikbaar maken ---"
  local_invalidate

  log INFO "--- stap 4: handmatige web-revoke ---"
  print_revoke_url

  # Manual revoke — --yes-neutralize mag deze NIET skippen.
  if ! confirm "Heb je de token in de browser ingetrokken?" 0; then
    log INFO "geen revoke-bevestiging — verify overgeslagen"
    send_mail_if_configured
    cleanup_if_clean_run
    exit 10
  fi

  log INFO "--- stap 5: verify ---"
  if verify_revoke; then
    log INFO "✓ token bevestigd revoked (HTTP 401)"
    send_mail_if_configured
    if [[ $INCIDENT_DIR_CREATED -eq 1 ]]; then
      log INFO "evidence + log: $INCIDENT_DIR (kopieer naar dossier als gewenst)"
    fi
    [[ $DEADMAN_FOUND -eq 1 ]] && exit 1 || exit 0
  else
    log ERROR "verify FAALDE — token kan nog actief zijn"
    log ERROR "Check $TOKENS_URL en bevestig dat juiste token is verwijderd"
    send_mail_if_configured
    exit 2
  fi
}

main "$@"
