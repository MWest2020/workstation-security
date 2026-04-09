#!/usr/bin/env bash
# install-timers.sh — systemd timers voor dagelijkse updates en scans
set -euo pipefail

UNIT_DIR="/etc/systemd/system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Dagelijkse signature/database update ---

cat > "$UNIT_DIR/av-update.service" <<UNIT
[Unit]
Description=ClamAV + rkhunter dagelijkse update

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/update.sh
UNIT

cat > "$UNIT_DIR/av-update.timer" <<'UNIT'
[Unit]
Description=Dagelijkse AV signature update (04:00)

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# --- Dagelijkse ClamAV scan ---

cat > "$UNIT_DIR/clamav-scan.service" <<'UNIT'
[Unit]
Description=ClamAV dagelijkse scan
After=clamav-freshclam.service

[Service]
Type=oneshot
ExecStart=/usr/bin/clamscan -r /home --infected --log=/var/log/clamav/daily-scan.log
UNIT

cat > "$UNIT_DIR/clamav-scan.timer" <<'UNIT'
[Unit]
Description=Dagelijkse ClamAV scan (02:00)

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# --- Dagelijkse rkhunter check ---

cat > "$UNIT_DIR/rkhunter-check.service" <<'UNIT'
[Unit]
Description=rkhunter dagelijkse rootkit check

[Service]
Type=oneshot
ExecStart=/usr/bin/rkhunter --check --skip-keypress --report-warnings-only --logfile /var/log/rkhunter.log
UNIT

cat > "$UNIT_DIR/rkhunter-check.timer" <<'UNIT'
[Unit]
Description=Dagelijkse rkhunter check (03:00)

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

mkdir -p /var/log/clamav

systemctl daemon-reload
systemctl enable --now av-update.timer
systemctl enable --now clamav-scan.timer
systemctl enable --now rkhunter-check.timer

echo "  Timers geïnstalleerd: av-update.timer, clamav-scan.timer, rkhunter-check.timer"
