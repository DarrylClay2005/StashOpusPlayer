# Stash Opus Player

A visually appealing Android music player with advanced features and support for multiple audio formats.

## Features

- **Multi-format Support**: Play Opus, MP3, FLAC, OGG, M4A, WAV, AAC, and WMA audio files
- **Custom Backgrounds**: Set your own image as the app background
- **Side Navigation**: Easy access to music library, playlists, equalizer, and settings
- **Modern UI**: Material Design 3 with dark theme
- **Audio Permissions**: Smart permission handling for Android 13+
- **Lightweight**: Optimized APK size (~4MB for release build)

## Screenshots

[Screenshots would go here in a real project]

## Installation

1. Download the latest APK from the [Releases](../../releases) page
2. Install on your Android device (requires Android 5.0+ / API 21+)
3. Grant audio permissions when prompted

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
