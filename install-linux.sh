#!/usr/bin/env bash
# install-linux.sh — one-time setup on Linux/macOS
# Sets up sync.py as a weekly systemd timer (Linux) or launchd plist (macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync.py"

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "ERROR: sync.py not found in $SCRIPT_DIR"
  exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
  # ── macOS: launchd ──────────────────────────────────────────────────────────
  PLIST="$HOME/Library/LaunchAgents/com.vcvrack.metamodule-sync.plist"
  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.vcvrack.metamodule-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which python3)</string>
    <string>$SYNC_SCRIPT</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>1</integer>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/.local/share/Rack2/sync.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.local/share/Rack2/sync.log</string>
</dict>
</plist>
EOF
  launchctl load "$PLIST"
  echo "Installed launchd plist: $PLIST (runs every Monday 9am)"

else
  # ── Linux: systemd user timer ───────────────────────────────────────────────
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"

  cat > "$SYSTEMD_DIR/vcvrack-metamodule-sync.service" << EOF
[Unit]
Description=VCV Rack MetaModule plugin sync
After=network-online.target

[Service]
Type=oneshot
ExecStart=$(which python3) $SYNC_SCRIPT
StandardOutput=journal
StandardError=journal
EOF

  cat > "$SYSTEMD_DIR/vcvrack-metamodule-sync.timer" << EOF
[Unit]
Description=Weekly VCV Rack MetaModule plugin sync

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now vcvrack-metamodule-sync.timer
  echo "Installed systemd user timer (runs weekly)"
  systemctl --user list-timers vcvrack-metamodule-sync.timer
fi

echo ""
echo "Run a manual sync anytime with:"
echo "  python3 $SYNC_SCRIPT"
