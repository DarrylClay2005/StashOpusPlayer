# StashOpusPlayer v10.7.16

Changes:
- Fixed track switching when selecting a new song mid-play: client sends CANCEL_CROSSFADE and the service cancels crossfade before replacing the queue.
- Queue persistence: save/restore items, index, position, shuffle/repeat across restarts.
- Notification custom actions: -10s, +30s seek, and Favorite toggle via Media3 PlayerNotificationManager custom actions.
- Queue editing: drag-to-reorder and swipe-to-remove in full-screen Queue.
- Context menu actions: Play Next and Add to Queue from song list/grid.
- Removed dead MediaActionReceiver (notification actions now routed via MediaSession).

Built on Sat Oct  4 21:41:51 UTC 2025.