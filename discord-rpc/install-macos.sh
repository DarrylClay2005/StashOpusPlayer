#!/usr/bin/env bash
# Sets up the Lumisound Discord Rich Presence daemon as a macOS LaunchAgent
# (runs in the background, restarts on login).
#
# Usage:
#   ./install-macos.sh <rpc_token> [bridge_url]
#
# Get <rpc_token> from Lumisound -> Account -> Discord Rich Presence ->
# Generate Rich Presence Token.

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <rpc_token> [bridge_url]" >&2
    echo "Get <rpc_token> from Lumisound -> Account -> Discord Rich Presence -> Generate Rich Presence Token." >&2
    exit 1
fi

ACCESS_TOKEN="$1"
BRIDGE_URL="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/lumisound-discord-rpc"
CONFIG_FILE="$CONFIG_DIR/config.json"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS_DIR/com.lumisound.discord-rpc.plist"

mkdir -p "$CONFIG_DIR" "$LAUNCH_AGENTS_DIR"

python3 - "$CONFIG_FILE" "$ACCESS_TOKEN" "$BRIDGE_URL" <<'EOF'
import json
import sys

config_file, access_token, bridge_url = sys.argv[1:4]

config = {
    "access_token": access_token,
    "poll_interval_seconds": 5,
}
if bridge_url:
    config["bridge_url"] = bridge_url

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
EOF

chmod 600 "$CONFIG_FILE"
echo "Wrote $CONFIG_FILE"

PYTHON3="$(command -v python3)"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lumisound.discord-rpc</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON3</string>
        <string>$SCRIPT_DIR/lumisound_discord_rpc.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/daemon.log</string>
</dict>
</plist>
PLIST_EOF

echo "Installed $PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo
echo "Started. Check status with:"
echo "  launchctl list | grep lumisound"
echo "  tail -f $CONFIG_DIR/daemon.log"
echo
echo "Stop with:"
echo "  launchctl unload $PLIST"
