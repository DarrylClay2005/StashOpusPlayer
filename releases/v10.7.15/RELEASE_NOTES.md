# StashOpusPlayer v10.7.15

Changes:
- Notification controls are now powered by Media3 PlayerNotificationManager and routed directly to the active MediaSession/ExoPlayer
  - Fixes flaky buttons and rare crashes from the previous broadcast action path
  - Added MEDIA_BUTTON intent filter for reliable headset/lockscreen control
- Artwork polish
  - Circular thumbnails in lists and grids; mini-player artwork is circular for consistency
  - Now Playing artwork remains square as requested
  - Fixed grid artwork disappearance/sizing by updating layouts and ensuring Glide respects view sizes
- Playback UX
  - Tapping a song queues the full visible list and starts at the selected track
  - Next/Previous, auto-next at track end, and shuffle all work (shuffle via ExoPlayer built-in)
- New screens
  - QueueActivity: full-screen queue viewer; selecting a track jumps playback
  - MetadataActivity: detailed track metadata from DB or MediaMetadataRetriever
  - Now Playing buttons open these screens
- System integration
  - Media session metadata/artwork provided for system controls; notification category set to transport
  - Cleaned up unsupported callbacks for Media3 compatibility
- Updater
  - Install permissions flow handled on Android 8+ (REQUEST_INSTALL_PACKAGES)

Built on Sat Oct  4 20:54:31 UTC 2025.
