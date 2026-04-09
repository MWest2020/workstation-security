#!/usr/bin/env bash
# update.sh — ClamAV signatures + rkhunter database bijwerken
# Probeert ook rkhunter te installeren als het nog niet aanwezig is maar nu wel beschikbaar via dnf
set -euo pipefail

echo "==> ClamAV signatures bijwerken..."
freshclam

echo "==> rkhunter..."
if command -v rkhunter &>/dev/null; then
  # Al geïnstalleerd — alleen database bijwerken
  rkhunter --update
  echo "  rkhunter database bijgewerkt."
elif dnf install -y rkhunter &>/dev/null 2>&1; then
  # Nieuw beschikbaar via dnf — installeren en initialiseren
  echo "  rkhunter nieuw beschikbaar — geïnstalleerd."
  rkhunter --update
  rkhunter --propupd
  echo "  rkhunter geïnitialiseerd."
else
  # Nog steeds niet beschikbaar (Alma 10)
  echo "  rkhunter niet beschikbaar — overgeslagen."
fi

echo "Klaar."
