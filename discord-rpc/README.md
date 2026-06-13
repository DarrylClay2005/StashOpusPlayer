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
   it (e.g. `lumisound_logo`).
3. Copy the **Application ID** (Client ID) from the General Information page.

## 2. Register it in Lumisound

In the app, go to **Account → Discord Rich Presence** and:

1. Tap **Generate Rich Presence Token** — this is the only credential the
   local daemon needs. It only allows reading your own playback state, not
   your password, and can be revoked any time from **Account → Active
   Sessions** ("Discord RPC Bridge") without changing your password.
2. Enter the **Application Client ID** from step 1 (and optionally the art
   asset name from step 1) and save. This is stored server-side
   (`/user/discord-rpc-config`) — the daemon fetches it automatically, so
   there's nothing to copy into a config file.

## 3. Configure the daemon

```sh
mkdir -p ~/.config/lumisound-discord-rpc
cp config.example.json ~/.config/lumisound-discord-rpc/config.json
```

Edit `~/.config/lumisound-discord-rpc/config.json`:

- `bridge_url`: base URL of your ios-bridge instance.
- `access_token`: the token from step 2.
- `poll_interval_seconds`: how often to refresh (default 5). Discord's local
  IPC rate-limits `SET_ACTIVITY` to about 1 call every 4 seconds, so 5s is
  close to the practical minimum for near-real-time updates.

Everything else (Discord Application client ID, art asset name, on/off) is
read from your account's server-side registration on every restart. You can
still set `discord_client_id` / `large_image` locally to override the
registered values, and `username` / `password` instead of `access_token` if
you'd rather log in directly — but the token + app registration above is the
recommended path, since each person just runs their own copy of this daemon
on their own machine with their own token.

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
