# Stash Opus Player

## Online Album Artwork (New)

When embedded artwork is missing, the player can fetch cover images online based on the current song's title and artist.

- Sources: MusicBrainz + Cover Art Archive (primary), iTunes Search (fallback)
- Caching: Images are stored under the app cache at runtime; subsequent plays load instantly.
- Toggle: Settings -> Album Artwork -> "Fetch album art online when missing"
- Privacy: Only the title/artist are sent as query terms. No audio files are uploaded.

Notes:
- A network connection is required. Respect provider rate limits.
- The app uses a generic User-Agent compliant with MusicBrainz guidelines.
- You can clear app cache to remove downloaded artwork.

A visually appealing Android music player with advanced features and support for multiple audio formats.

## Features

### 🎵 Audio & Playback
- **Multi-format Support**: Play Opus, MP3, FLAC, OGG, M4A, WAV, AAC, and WMA audio files
- **10-Band Equalizer**: Professional audio tuning with preset and custom settings
- **ExoPlayer Integration**: High-quality, gapless audio playback
- **Full Metadata Support**: Artist, album, genre, and artwork display

### 🎨 User Interface
- **Modern UI**: Material Design 3 with enhanced Now Playing interface
- **Custom Backgrounds**: Set your own image as the app background
- **Side Navigation**: Easy access to music library, playlists, equalizer, and settings
- **Album Art Display**: Beautiful artwork integration throughout the app

### 🔧 Technical
- **Smart Permissions**: Intelligent permission handling for Android 13+
- **AI Update Checker**: Automated update detection system
- **Reliable Installation**: Fixed APK signing issues for seamless installation
- **Professional Icon**: Multimedia audio player icon design

## Screenshots

[Screenshots would go here in a real project]

## Installation

1. Download the latest **v3.0.1 release APK** from the [Releases](../../releases) page
   - Use **StashOpusPlayer-v3.0.1-release-properly-signed.apk** for guaranteed installation
2. Enable "Unknown Sources" in your Android settings if prompted
3. Install the APK on your Android device (requires Android 5.0+ / API 21+)
4. Grant audio and storage permissions when prompted
5. Enjoy your music with the full-featured player!

### 🔧 Installation Fix (v3.0.1)
If you experienced "package appears to be invalid" errors with v3.0, v3.0.1 resolves all APK signing issues for seamless installation.

**Note**: If upgrading from earlier versions, you may need to uninstall the previous version first.

## Development

### Prerequisites

- Android SDK
- Java 17+
- Gradle

### Building

```bash
# Debug build
./gradlew assembleDebug

# Release build  
./gradlew assembleRelease
```

### Project Structure

```
app/
├── src/main/java/com/stash/opusplayer/
│   ├── ui/                 # Activities and fragments
│   ├── service/           # Music playback service
│   ├── data/              # Data models and repository
│   └── utils/             # Utility classes
└── src/main/res/          # Resources (layouts, drawables, etc.)
```

## Technologies Used

- **Kotlin** - Primary development language
- **Android Jetpack** - Architecture components
- **ExoPlayer (Media3)** - High-quality audio playback
- **Material Design 3** - Modern UI components
- **Glide** - Image loading and caching
- **Dexter** - Permission handling

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

**Note**: This is an open-source music player. Make sure you have the rights to play any audio files you use with this application.
