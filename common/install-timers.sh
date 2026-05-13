#!/usr/bin/env bash
# install-timers.sh — systemd timers voor dagelijkse updates en scans.
# Heredocs hieronder zijn de canonieke unit-definities; namen moeten matchen
# met WS_TIMERS / WS_SERVICES_GENERATED in common/lib.sh (smoke-test onderaan).
# Style-afwijking: shebang via `env bash` i.p.v. `/bin/bash` — repo target
# o.a. macOS; rest van repo gebruikt al `env bash`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly UNIT_DIR="/etc/systemd/system"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

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

cat > "$UNIT_DIR/clamav-scan.service" <<UNIT
[Unit]
Description=ClamAV dagelijkse scan
After=clamav-freshclam.service

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/scan.sh
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

cat > "$UNIT_DIR/rkhunter-check.service" <<UNIT
[Unit]
Description=rkhunter dagelijkse rootkit check

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/rkhunter-check.sh
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

# --- Logrotate ---

cp "$SCRIPT_DIR/logrotate.conf" /etc/logrotate.d/workstation-security

# --- Drift-smoke-test: zijn alle WS_TIMERS heredocs ook daadwerkelijk geschreven? ---
for unit in "${WS_TIMERS[@]}" "${WS_SERVICES_GENERATED[@]}"; do
  if [[ ! -f "$UNIT_DIR/$unit" ]]; then
    echo "error: lib.sh noemt $unit maar het is niet door dit script geschreven —" >&2
    echo "       drift tussen WS_TIMERS/WS_SERVICES_GENERATED en de heredocs." >&2
    exit 2
  fi
done

systemctl daemon-reload
for timer in "${WS_TIMERS[@]}"; do
  systemctl enable --now "$timer"
done

echo "  Timers geïnstalleerd: ${WS_TIMERS[*]}"
