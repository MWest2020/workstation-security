#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# rkhunter-check.sh — dagelijkse rkhunter check met notificatie bij waarschuwingen.
# Style-afwijking: shebang `env bash` voor consistentie met repo. `set -e` UIT:
# rkhunter --check retourneert non-zero bij gevonden warnings — dat is precies
# wat we moeten DETECTEREN (en via `wall` melden), niet aborten op.
#
# Usage:
#   sudo bash common/rkhunter-check.sh   # rkhunter scant /etc, /usr, /bin — root nodig
#   # Doorgaans aangeroepen door ws-rkhunter.timer (dagelijks)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LOG="/var/log/rkhunter.log"

# WSL-skip: rkhunter geeft hier veel false-positives op /proc-checks, op de
# passwd-checks rond WSL's init-proces, en op system_configs.t (verwacht
# echte init-scripts). Een daily wall-notificatie met onbetrouwbare
# waarschuwingen leidt tot alarm-fatigue — dat is op zichzelf al een ISO
# 27001-bevinding ("medewerkers negeren security-alerts"). Plus: WSL's
# container-achtige isolatie verandert het rootkit-bedreigingsmodel
# fundamenteel; de Windows-host is daar de relevante verdedigingslaag
# (Defender / EDR). Boring en auditeerbaar: niet draaien wat niet zinvol is.
if ws_is_wsl; then
  echo "rkhunter overgeslagen op WSL — false-positives op /proc en init-checks."
  echo "Rootkit-bedreigingsmodel verschilt op WSL (container-isolatie);"
  echo "gebruik Microsoft Defender / een Windows-AV op de Windows-host."
  exit 0
fi

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
