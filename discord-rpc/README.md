# Lumisound Discord Rich Presence

A small local daemon that mirrors your Lumisound "now playing" state to your
Discord profile via Rich Presence.

This only works on a machine running the Discord desktop client, because
Rich Presence is set over a local IPC socket (`discord-ipc-*` under
`$XDG_RUNTIME_DIR`) — it can't be driven remotely from the iOS app.

## 1. Create a Discord application

1. Go to https://discord.com/developers/applications and click **New
   Application**. Give it a name (e.g. "Lumisound") — this name is what
   shows up in the Rich Presence card.
2. (Optional) Under **Rich Presence > Art Assets**, upload an image and name
   it (e.g. `lumisound_logo`). Use that name as `large_image` in your config.
3. Copy the **Application ID** (Client ID) from the General Information page.

## 2. Configure

```sh
mkdir -p ~/.config/lumisound-discord-rpc
cp config.example.json ~/.config/lumisound-discord-rpc/config.json
```

Edit `~/.config/lumisound-discord-rpc/config.json`:

- `discord_client_id`: the Application ID from step 1.
- `bridge_url`: base URL of your ios-bridge instance.
- `username` / `password`: your Lumisound account credentials. On first run
  the daemon logs in and saves the resulting access token back into this
  file, so the password is only used once (until the token expires after 30
  days, at which point it logs in again automatically).
- `poll_interval_seconds`: how often to refresh (default 5). Discord's local
  IPC rate-limits `SET_ACTIVITY` to about 1 call every 4 seconds, so 5s is
  close to the practical minimum for near-real-time updates.
- `large_image`: optional asset name from step 2.

## 3. Run it

Directly, for testing:

```sh
python3 lumisound_discord_rpc.py
```

Or as a systemd user service (keeps running across logins/reboots):

```sh
mkdir -p ~/.config/systemd/user
cp lumisound-discord-rpc.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now lumisound-discord-rpc.service
```

Check status / logs:

```sh
systemctl --user status lumisound-discord-rpc.service
journalctl --user -u lumisound-discord-rpc.service -f
```

## How it works

The daemon polls `GET /user/playback-state` on the bridge. Whenever
Lumisound's iOS app reports a track via the existing playback-state sync,
this daemon picks it up and calls `SET_ACTIVITY` over Discord's local IPC
socket, showing:

- **Details**: track title
- **State**: `by <artist>`
- **Timestamps**: elapsed/remaining bar based on `position_seconds` /
  `duration_seconds`

If playback is paused or the last update is older than 2 minutes (app
backgrounded/closed), the Rich Presence is cleared.
