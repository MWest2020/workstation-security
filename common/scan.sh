#!/usr/bin/env bash
# scan.sh — dagelijkse ClamAV scan met exclude-patterns en notificatie bij vondsten
set -uo pipefail

LOG="/var/log/clamav/daily-scan.log"

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
  --exclude-dir='__pycache__'
rc=$?

if [[ $rc -eq 1 ]]; then
  wall "ClamAV: infecties gevonden op $(hostname)! Zie $LOG" 2>/dev/null || true
fi

exit 0
