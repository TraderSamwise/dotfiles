#!/usr/bin/env bash
# Schedule agent-config-apply so a model line changed behind our back is corrected
# within hours instead of at the next provisioning. Idempotent on both platforms.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APPLY="$HOME/.local/bin/agent-config-apply"
LABEL="com.sam.agent-config-apply"
INTERVAL=21600 # 6 hours

[ -x "$APPLY" ] || APPLY="$DOTFILES/bin/agent-config-apply"

case "$(uname -s)" in
Darwin)
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$(dirname "$PLIST")" "$HOME/.local/state"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APPLY</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>StandardOutPath</key><string>$HOME/.local/state/agent-config-apply.log</string>
  <key>StandardErrorPath</key><string>$HOME/.local/state/agent-config-apply.log</string>
</dict>
</plist>
PLISTEOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "timer  launchd $LABEL every ${INTERVAL}s"
  ;;
Linux)
  UNITS="$HOME/.config/systemd/user"
  mkdir -p "$UNITS" "$HOME/.local/state"
  cat > "$UNITS/$LABEL.service" <<UNITEOF
[Unit]
Description=Force agent CLIs onto the declared models

[Service]
Type=oneshot
ExecStart=$APPLY
UNITEOF
  cat > "$UNITS/$LABEL.timer" <<UNITEOF
[Unit]
Description=Re-apply declared agent models every 6h

[Timer]
OnBootSec=5min
OnUnitActiveSec=${INTERVAL}s
Persistent=true

[Install]
WantedBy=timers.target
UNITEOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$LABEL.timer"
  echo "timer  systemd $LABEL.timer every ${INTERVAL}s"
  ;;
*)
  echo "!! unsupported platform $(uname -s); schedule $APPLY yourself" >&2
  ;;
esac
