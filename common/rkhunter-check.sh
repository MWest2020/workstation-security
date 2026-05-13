#!/usr/bin/env bash
# rkhunter-check.sh — dagelijkse rkhunter check met notificatie bij waarschuwingen.
# Style-afwijking: shebang `env bash` voor consistentie met repo. `set -e` UIT:
# rkhunter --check retourneert non-zero bij gevonden warnings — dat is precies
# wat we moeten DETECTEREN (en via `wall` melden), niet aborten op.
set -uo pipefail

LOG="/var/log/rkhunter.log"

if ! command -v rkhunter &>/dev/null; then
  echo "rkhunter niet geïnstalleerd — overgeslagen."
  exit 0
fi

rkhunter --check --skip-keypress --report-warnings-only --logfile "$LOG"
rc=$?

if [[ $rc -ne 0 ]]; then
  wall "rkhunter: waarschuwingen gevonden op $(hostname)! Zie $LOG" 2>/dev/null || true
fi

exit 0
