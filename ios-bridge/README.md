# Lumisound iOS Bridge

A minimal FastAPI server that wraps yt-dlp to give the Lumisound iOS app
YouTube and SoundCloud search plus on-demand stream URL resolution.

## Run

```bash
docker-compose up -d
```

The server listens on port **7333**.

## Add to an existing docker-compose

Copy the `ios-bridge` service block from `docker-compose.yml` into your existing
compose file. Because `network_mode: "host"` is already used by the music bots
the service will resolve correctly without any port-mapping changes.

## API Endpoints

| Method | Path | Query params | Description |
|--------|------|-------------|-------------|
| GET | `/health` | — | Liveness check |
| GET | `/api/search` | `q`, `limit` (default 20), `source` (youtube\|soundcloud) | Search tracks |
| GET | `/api/stream` | `id`, `source`, `url` (SC only) | Get direct stream URL |
| GET | `/api/track` | `url` | Metadata for a single URL |
| GET | `/api/resolve` | `url` | Expand playlist/album into tracks (max 50) |

## iOS app configuration

Open the app → **Settings** → **Streaming** section:

- **Server URL** — e.g. `http://192.168.1.x:7333`
- **API Key** — leave blank unless you set `IOS_BRIDGE_API_KEY` in the compose env

## Optional API key auth

```bash
IOS_BRIDGE_API_KEY=mysecret docker-compose up -d
```

All endpoints except `/health` then require `Authorization: Bearer mysecret`.

## Automatic host-side YouTube cookie refresh

The bridge writes `cache/yt-dlp/.cookies_stale` when yt-dlp reports that the
operator's YouTube cookies are no longer valid. The checked-in
`refresh_youtube_cookies.sh` helper can then re-export cookies from an
explicitly configured, logged-in host browser. It must run on the host (never
inside the bridge container), because browser profiles and keyrings must not
be mounted into the container.

Install yt-dlp on the host, configure the browser explicitly, and install the
user systemd units:

```bash
cd /path/to/Lumisound/ios-bridge
mkdir -p ~/.local/bin ~/.config/systemd/user
cp refresh_youtube_cookies.sh ~/.local/bin/lumisound-refresh-youtube-cookies
chmod 700 ~/.local/bin/lumisound-refresh-youtube-cookies
cp lumisound-youtube-cookies-refresh.{service,path,timer} ~/.config/systemd/user/
mkdir -p ~/.config
cat > ~/.config/lumisound-youtube-cookies.env <<'EOF'
YTDLP_BROWSER=firefox
YTDLP_COOKIES_FILE=/path/to/Lumisound/ios-bridge/cookies.txt
YTDLP_CACHE_DIR=/path/to/Lumisound/ios-bridge/cache/yt-dlp
# Optional: a profile/keyring/container can be included in the yt-dlp spec.
# Example: YTDLP_BROWSER=chrome+gnomekeyring:/home/me/.config/google-chrome
EOF
```

The copied service unit reads
`%h/.config/lumisound-youtube-cookies.env` automatically. Change the `.path`
unit's `PathChanged` (and `PathExists`) if the checkout is not under
`%h/Documents/Projects/Lumisound`, then enable the units:

```bash
systemctl --user daemon-reload
systemctl --user enable --now lumisound-youtube-cookies-refresh.path
systemctl --user enable --now lumisound-youtube-cookies-refresh.timer
```

A refresh is installed only after structural YouTube/session-cookie checks pass
and an atomic replacement succeeds; failures leave the previous file and
sentinel untouched. The helper never prints cookie contents.
