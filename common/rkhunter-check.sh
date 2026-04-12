#!/usr/bin/env bash
# rkhunter-check.sh — dagelijkse rkhunter check met notificatie bij waarschuwingen
set -uo pipefail

LOG="/var/log/rkhunter.log"

rkhunter --check --skip-keypress --report-warnings-only --logfile "$LOG"
rc=$?

if [[ $rc -ne 0 ]]; then
  wall "rkhunter: waarschuwingen gevonden op $(hostname)! Zie $LOG" 2>/dev/null || true
fi

exit 0
