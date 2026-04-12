#!/usr/bin/env bash
# update.sh — ClamAV signatures + rkhunter database bijwerken
# Probeert ook rkhunter te installeren als het nog niet aanwezig is maar nu wel beschikbaar via dnf/pacman/apt
set -euo pipefail

echo "==> ClamAV signatures bijwerken..."
freshclam

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
