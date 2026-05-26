#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# update.sh — ClamAV signatures + rkhunter database bijwerken
# Probeert ook rkhunter te installeren als het nog niet aanwezig is maar nu wel beschikbaar via dnf/pacman/apt
#
# Usage:
#   sudo bash common/update.sh    # update ClamAV sigs + rkhunter db; ook aangeroepen door ws-update.timer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=install-base.sh disable=SC1091
source "${SCRIPT_DIR}/install-base.sh"

ws_handle_version "$@"

echo "==> ClamAV signatures bijwerken..."
# freshclam_safe is een defensieve safety net: na een schone install van
# deze repo staat clamav-freshclam.service uit (zie disable_freshclam_daemon
# in install-base.sh) en is de `systemctl stop` een no-op. Maar op gemigreerde
# installs of na een dnf/apt pakket-update kan de daemon alsnog aanstaan; dan
# houdt hij de log-lock vast en faalt freshclam silently. Audit-relevant:
# een AV met stale signatures is een non-conformity.
freshclam_safe

echo "==> rkhunter..."
if command -v rkhunter &>/dev/null; then
  # Al geïnstalleerd — alleen database bijwerken
  rkhunter --update
  echo "  rkhunter database bijgewerkt."
elif command -v dnf &>/dev/null && dnf install -y rkhunter &>/dev/null 2>&1; then
  echo "  rkhunter nieuw beschikbaar via dnf — geïnstalleerd."
  rkhunter --update
  rkhunter --propupd
  echo "  rkhunter geïnitialiseerd."
elif command -v pacman &>/dev/null && pacman -S --noconfirm rkhunter &>/dev/null 2>&1; then
  echo "  rkhunter nieuw beschikbaar via pacman — geïnstalleerd."
  rkhunter --update
  rkhunter --propupd
  echo "  rkhunter geïnitialiseerd."
elif command -v apt-get &>/dev/null && apt-get install -y rkhunter &>/dev/null 2>&1; then
  echo "  rkhunter nieuw beschikbaar via apt — geïnstalleerd."
  rkhunter --update
  rkhunter --propupd
  echo "  rkhunter geïnitialiseerd."
else
  echo "  rkhunter niet beschikbaar — overgeslagen."
fi

echo "Klaar."
