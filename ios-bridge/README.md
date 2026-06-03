# StashOpusPlayer iOS Bridge

A minimal FastAPI server that wraps yt-dlp to give the StashOpusPlayer iOS app
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
