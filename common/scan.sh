#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# scan.sh — dagelijkse ClamAV scan met exclude-patterns en notificatie bij vondsten.
# Style-afwijking: shebang `env bash` voor consistentie met repo. `set -e` UIT:
# clamscan retourneert exit 1 bij gevonden infecties — dat is precies wat we
# moeten DETECTEREN (en via `wall` melden), niet aborten op.
#
# Usage:
#   bash common/scan.sh                  # interactieve scan (geen root nodig voor $HOME)
#   # Doorgaans aangeroepen door ws-scan.timer (dagelijks)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LOG="/var/log/clamav/daily-scan.log"

# WSL: sluit /mnt uit (Windows-drives via DrvFs). Native Linux: /mnt is
# vaak een legitieme mount voor tijdelijke media — daar wél scannen.
# Bouw exclude-args dynamisch op zodat de clamscan-call portable blijft.
extra_excludes=()
if ws_is_wsl; then
  extra_excludes+=(--exclude-dir='^/mnt/')
fi

clamscan -r /home \
  --infected \
  --log="$LOG" \
  --exclude-dir='\.cache' \
  --exclude-dir='\.git' \
  --exclude-dir='\.gradle' \
  --exclude-dir='\.m2' \
  --exclude-dir='\.npm' \
  --exclude-dir='\.cargo/registry' \
  --exclude-dir='\.rustup' \
  --exclude-dir='\.venv' \
  --exclude-dir='\.local/share/Steam' \
  --exclude-dir='node_modules' \
  --exclude-dir='__pycache__' \
  "${extra_excludes[@]}"
rc=$?

if [[ $rc -eq 1 ]]; then
  wall "ClamAV: infecties gevonden op $(hostname)! Zie $LOG" 2>/dev/null || true
fi

exit 0
