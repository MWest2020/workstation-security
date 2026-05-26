#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Ubuntu/Debian (apt).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash ubuntu/install.sh             # apt install ClamAV + rkhunter, enable services, install timers
#   bash ubuntu/install.sh --dry-run        # print zou-uitgevoerd-zijn commando's, geen wijzigingen
#   bash ubuntu/install.sh --version        # print versie en exit

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../common/install-base.sh"

ws_parse_install_args "ubuntu/install.sh" "$@"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
ws_run_or_print apt-get update
if ws_is_dry_run; then
  ws_run_or_print apt-get install -y clamav clamav-daemon
  clamav_ok=1
elif apt-get install -y clamav clamav-daemon; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> Services aanzetten..."
# clamav-freshclam.service uit zetten — av-update.timer doet de signature-
# update om 04:00; twee mechanismen race'n op de freshclam log-lock.
disable_freshclam_daemon
enable_clamav_services clamav-daemon

echo "==> rkhunter installeren..."
# Geen `2>/dev/null` op de echte run: apt-failure-reasons willen we zien
# (held-back, key-verlopen, etc.) i.p.v. silent skip. rkhunter_init wrapt
# zelf set +e/-e rond --update en --propupd (rkhunter 1.4 + deprecated
# egrep — zie install-base.sh).
if ws_is_dry_run; then
  ws_run_or_print apt-get install -y rkhunter
  rkhunter_init
  rkhunter_ok=1
elif apt-get install -y rkhunter; then
  if rkhunter_init; then
    rkhunter_ok=1
  else
    echo "  rkhunter init kreeg non-zero exit (zie ws_warn hierboven)."
    echo "  Controleer:  sudo ls -l /var/lib/rkhunter/db/rkhunter.dat"
    echo "  Ontbreekt de .dat? Draai dan handmatig: sudo rkhunter --propupd"
  fi
else
  echo "  rkhunter niet beschikbaar via apt — wordt overgeslagen."
fi

echo "==> Timers installeren..."
install_timers

if ws_is_dry_run; then
  echo ""
  echo "(dry-run; no changes made)"
  exit 0
fi

print_summary "$clamav_ok" "$rkhunter_ok" "apt"

exit 0
