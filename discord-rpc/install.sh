#!/usr/bin/env bash
# Sets up the Lumisound Discord Rich Presence daemon as a systemd --user service.
#
# Usage:
#   ./install.sh <discord_client_id> <bridge_url> <username> <password> [large_image]
#
# Example:
#   ./install.sh 1234567890123456 https://lumisound.example.com alice mypassword lumisound_logo

set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <discord_client_id> <bridge_url> <username> <password> [large_image]" >&2
    exit 1
fi

DISCORD_CLIENT_ID="$1"
BRIDGE_URL="$2"
USERNAME="$3"
PASSWORD="$4"
LARGE_IMAGE="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/lumisound-discord-rpc"
CONFIG_FILE="$CONFIG_DIR/config.json"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

mkdir -p "$CONFIG_DIR" "$SYSTEMD_USER_DIR"

python3 - "$CONFIG_FILE" "$DISCORD_CLIENT_ID" "$BRIDGE_URL" "$USERNAME" "$PASSWORD" "$LARGE_IMAGE" <<'EOF'
import json
import sys

config_file, client_id, bridge_url, username, password, large_image = sys.argv[1:7]

config = {
    "discord_client_id": client_id,
    "bridge_url": bridge_url,
    "username": username,
    "password": password,
    "poll_interval_seconds": 15,
}
if large_image:
    config["large_image"] = large_image

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
EOF

chmod 600 "$CONFIG_FILE"
echo "Wrote $CONFIG_FILE"

cp "$SCRIPT_DIR/lumisound-discord-rpc.service" "$SYSTEMD_USER_DIR/"
echo "Installed $SYSTEMD_USER_DIR/lumisound-discord-rpc.service"

systemctl --user daemon-reload
systemctl --user enable --now lumisound-discord-rpc.service

echo
echo "Service started. Check status with:"
echo "  systemctl --user status lumisound-discord-rpc.service"
echo "  journalctl --user -u lumisound-discord-rpc.service -f"
