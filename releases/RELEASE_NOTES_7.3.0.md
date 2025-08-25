# Stash Opus Player v7.3.0

Performance and stability update focused on fast album art thumbnails.

Changes:
- Performance: Embedded album art is now saved to the on-device artwork cache during metadata extraction, enabling instant thumbnail loads across the app.
- Efficiency: Downsampled decode (RGB_565 + inSampleSize) and JPEG compression tuned for low memory and fast Glide rendering.
- Consistency: Unified artwork cache usage across activities and adapters to avoid duplicate work and conflicts.
- Stability: Defensive error handling to prevent OOM/crashes when parsing very large embedded images.

