#!/usr/bin/env bash
# Sets up the Lumisound Discord Rich Presence daemon as a systemd --user service.
#
# This is the only thing most people need to run. Everything else (Discord
# Application client ID, art asset, on/off) comes from your account's
# server-side registration in Lumisound -> Account -> Discord Rich Presence.
#
# Usage:
#   ./install.sh <rpc_token> [bridge_url]
#
# Example:
#   ./install.sh eyJhbGciOi...   # token from "Generate Rich Presence Token"

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
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

mkdir -p "$CONFIG_DIR" "$SYSTEMD_USER_DIR"

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

# Point the service at this checkout (works wherever it was cloned to).
sed "s#__SCRIPT_PATH__#$SCRIPT_DIR/lumisound_discord_rpc.py#" \
    "$SCRIPT_DIR/lumisound-discord-rpc.service" > "$SYSTEMD_USER_DIR/lumisound-discord-rpc.service"
echo "Installed $SYSTEMD_USER_DIR/lumisound-discord-rpc.service"

systemctl --user daemon-reload
systemctl --user enable --now lumisound-discord-rpc.service

echo
echo "Service started. Check status with:"
echo "  systemctl --user status lumisound-discord-rpc.service"
echo "  journalctl --user -u lumisound-discord-rpc.service -f"
