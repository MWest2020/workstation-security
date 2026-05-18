#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# common/check-shell-headers.sh — valideer dat elke shell-script conform
# de project-conventie een correct header heeft. Bedoeld als pre-commit
# hook (zie common/templates/pre-commit-config-shell.yaml.example) en als
# standalone audit-tool.
#
# Conventies gecontroleerd:
#   1. Shebang `#!/usr/bin/env bash` of `#!/bin/bash` op regel 1
#   2. SPDX-License-Identifier in eerste 5 regels
#   3. `# role: <entrypoint|library|container-entrypoint|installer|tool>` marker
#   4. `set -euo pipefail` aanwezig — alleen voor role=entrypoint of installer
#      (libraries inheriten van parent shell; tools mogen zelf kiezen)
#   5. Usage-comment block voor role=entrypoint, installer, tool
#
# Idempotent: alleen-lezen, geen side effects.
#
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   bash common/check-shell-headers.sh <file.sh> [<file2.sh> ...]
#   bash common/check-shell-headers.sh --all <dir>     # alle .sh files in dir
#   bash common/check-shell-headers.sh --pre-commit    # files uit stdin (pre-commit mode)
#
# Exit:
#   0 — alle files conform
#   1 — minstens één file violation
#   2 — gebruiksfout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

violations=0

# ---------------------------------------------------------------------------
# check_one <file>
# ---------------------------------------------------------------------------
check_one() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    ws_fail "${file}: file not found"
    violations=$((violations + 1))
    return
  fi

  local file_violations=0
  local head
  head="$(head -30 "$file")"

  # 1. shebang
  local first_line
  first_line="$(head -1 "$file")"
  if [[ "$first_line" != "#!/usr/bin/env bash" && "$first_line" != "#!/bin/bash" ]]; then
    ws_fail "${file}:1 — shebang missing or non-standard (got: '${first_line}')"
    file_violations=$((file_violations + 1))
  fi

  # 2. SPDX
  if ! echo "$head" | head -5 | grep -q 'SPDX-License-Identifier:'; then
    ws_fail "${file} — SPDX-License-Identifier missing in first 5 lines"
    file_violations=$((file_violations + 1))
  fi

  # 3. role marker
  local role=""
  if ! role="$(echo "$head" | grep -oE '^# role: [a-z-]+' | head -1 | awk '{print $3}')"; then
    : # grep error, treat as missing
  fi
  if [[ -z "$role" ]]; then
    ws_fail "${file} — '# role: <entrypoint|library|container-entrypoint|installer|tool>' marker missing"
    file_violations=$((file_violations + 1))
  else
    case "$role" in
      entrypoint|library|container-entrypoint|installer|tool) ;;
      *)
        ws_fail "${file} — unknown role '${role}' (must be entrypoint|library|container-entrypoint|installer|tool)"
        file_violations=$((file_violations + 1))
        ;;
    esac
  fi

  # 4. set -euo pipefail — required for entrypoint and installer
  if [[ "$role" == "entrypoint" || "$role" == "installer" ]]; then
    if ! grep -qE '^set -[a-z]*e[a-z]*u[a-z]* +-o +pipefail|^set -euo pipefail' "$file"; then
      ws_fail "${file} — role=${role} requires 'set -euo pipefail'"
      file_violations=$((file_violations + 1))
    fi
  fi

  # 5. Usage block — required for entrypoint, installer, tool
  if [[ "$role" == "entrypoint" || "$role" == "installer" || "$role" == "tool" ]]; then
    if ! echo "$head" | grep -qiE '^#[[:space:]]*usage:'; then
      ws_fail "${file} — role=${role} requires a '# Usage:' block in header"
      file_violations=$((file_violations + 1))
    fi
  fi

  if [[ "$file_violations" -eq 0 ]]; then
    ws_ok "${file}"
  else
    violations=$((violations + file_violations))
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local mode="files"
  local target=""
  local files=()

  if [[ $# -eq 0 ]]; then
    ws_fail "Usage: $0 <file.sh> [...] | --all <dir> | --pre-commit"
    exit 2
  fi

  case "$1" in
    --all)
      mode="all"; target="${2:-}"; shift 2 || true
      if [[ -z "$target" || ! -d "$target" ]]; then
        ws_fail "--all needs a directory argument"; exit 2
      fi
      ;;
    --pre-commit)
      mode="stdin"; shift
      ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# //;s/^#$//'
      exit 0
      ;;
  esac

  case "$mode" in
    all)
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$target" -type f -name '*.sh')
      ;;
    stdin)
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ "$f" == *.sh ]] && files+=("$f")
      done
      ;;
    files)
      files=("$@")
      ;;
  esac

  if [[ ${#files[@]} -eq 0 ]]; then
    ws_info "Geen .sh files om te checken."
    exit 0
  fi

  ws_info "Checking ${#files[@]} shell file(s)..."
  echo
  for f in "${files[@]}"; do
    check_one "$f"
  done

  echo
  if [[ "$violations" -eq 0 ]]; then
    ws_ok "Alle files conform."
    exit 0
  else
    ws_fail "${violations} violation(s) — fix bovenstaande issues."
    exit 1
  fi
}

main "$@"
