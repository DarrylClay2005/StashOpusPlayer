#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.nix-profile/bin:/etc/profiles/per-user/${USER}/bin:/run/current-system/sw/bin:${PATH:-}"

PORT="${1:-8002}"
HEALTH_URL="http://127.0.0.1:${PORT}/health"

echo "Waiting for iOS bridge on ${HEALTH_URL} (up to 300s)..."
for i in $(seq 1 150); do
    if curl -fsS --max-time 5 "${HEALTH_URL}" >/dev/null 2>&1; then
        echo "iOS bridge is ready."
        break
    fi
    if [[ "${i}" -eq 150 ]]; then
        echo "iOS bridge did not become ready in 300s; exiting." >&2
        exit 1
    fi
    sleep 2
done

echo "Starting cloudflared tunnel: lumisound-bridge.xenusanimations.studio -> localhost:${PORT}"
exec cloudflared tunnel --config "${HOME}/.cloudflared/config.yml" run lumisound-bridge
