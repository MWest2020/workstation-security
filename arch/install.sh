#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# install.sh — ClamAV + rkhunter voor Arch Linux (pacman).
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Usage:
#   sudo bash arch/install.sh    # pacman -S ClamAV + rkhunter, enable services, install timers

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/../common/install-base.sh"

require_root "arch/install.sh"

clamav_ok=0
rkhunter_ok=0

echo "==> Packages installeren..."
# -Syu (niet -Sy): partial-upgrade is op Arch een footgun. -Sy ververst alleen
# de package-database; geïnstalleerde packages blijven hun oude versie houden
# en verse dependencies matchen niet meer. Arch-community behandelt dit
# consistent als bug. Met --noconfirm gewoon meteen alles bijwerken.
if pacman -Syu --noconfirm clamav; then
  clamav_ok=1
else
  echo "  FOUT: ClamAV installatie mislukt." >&2
  exit 2
fi

# Quirk: pacman maakt /var/lib/clamav niet altijd aan met juiste eigenaar.
echo "==> ClamAV state-dir voorbereiden..."
mkdir -p /var/lib/clamav
chown clamav:clamav /var/lib/clamav

echo "==> Signatures downloaden..."
freshclam_safe

echo "==> Services aanzetten..."
# clamav-freshclam.service uit zetten — av-update.timer doet de signature-
# update om 04:00; twee mechanismen race'n op de freshclam log-lock.
disable_freshclam_daemon
enable_clamav_services clamav-daemon

echo "==> rkhunter installeren..."
if pacman -S --noconfirm rkhunter 2>/dev/null; then
  # Quirk: rkhunter in Arch gebruikt deprecated egrep en geeft non-zero exit
  # bij --update; --propupd is wel betrouwbaar. set -e tijdelijk uit om
  # vroegtijdig exit te voorkomen.
  set +e
  rkhunter_init
  set -e
  rkhunter_ok=1
else
  echo "  rkhunter niet beschikbaar via pacman — wordt overgeslagen."
fi

echo "==> Timers installeren..."
install_timers

print_summary "$clamav_ok" "$rkhunter_ok" "pacman"

exit 0
