# Stash Opus Player v8.1.6 Release Notes

## 📅 Release Date
December 26, 2024

## 🎯 Overview
Version 8.1.6 focuses on fixing and refining the pure yt-dlp + FFmpeg integration introduced in v8.1.5, ensuring reliable YouTube audio downloads with enhanced error handling and stability improvements.

## 🚀 Key Improvements

### Core Download System
- **Enhanced yt-dlp Integration**: Fixed issues with yt-dlp initialization and command execution
- **Improved Error Handling**: Better error messages and recovery mechanisms for failed downloads
- **Optimized FFmpeg Processing**: Enhanced audio processing pipeline with better quality preservation
- **Refined Anti-Detection**: Updated headers and user-agent rotation to maintain download reliability

### User Experience
- **Better Progress Feedback**: More accurate download progress reporting
- **Cleaner Error Messages**: User-friendly error descriptions with actionable solutions
- **Faster App Startup**: Optimized resource loading for quicker launch times
- **Improved UI Responsiveness**: Better thread management for smoother user interactions

### Technical Fixes
- **Memory Management**: Fixed potential memory leaks in download operations
- **Connection Stability**: Enhanced network timeout handling and retry logic
- **Format Selection**: Improved automatic audio format selection based on availability
- **Metadata Processing**: Better handling of video metadata extraction and embedding

## 📱 Installation

### New Installation
1. Download `StashOpusPlayer-v8.1.6-release.apk`
2. Enable "Install from unknown sources" in Android settings
3. Install the APK file
4. Grant necessary permissions when prompted

### Upgrading from Previous Version
1. Download the new APK
2. Install over the existing version (settings and downloads will be preserved)
3. Restart the app to ensure all components are properly updated

## 🔧 Technical Details

### Architecture
- **Pure yt-dlp Integration**: No external APIs or demo content - all downloads are real
- **Embedded FFmpeg**: Local audio processing without cloud dependencies
- **Advanced Anti-Detection**: Multiple strategies to maintain download success rates
- **Efficient Storage**: Smart caching and cleanup mechanisms

### Supported Formats
- **Audio**: MP3, M4A, OGG, WEBM, AAC, OPUS
- **Quality**: Automatic best quality selection with manual override options
- **Metadata**: Full support for title, artist, album, artwork embedding

### Security & Privacy
- **No Data Collection**: All operations are performed locally
- **No External Services**: Direct YouTube integration without third-party APIs
- **Secure Downloads**: Verified SSL/TLS connections for all network operations

## 🐛 Bug Fixes
- Fixed yt-dlp initialization errors on first launch
- Resolved audio format selection issues
- Fixed progress reporting inconsistencies
- Corrected metadata extraction for certain video types
- Improved error recovery for network interruptions

## 🛠️ For Developers

### Build Information
- **Target SDK**: 34 (Android 14)
- **Minimum SDK**: 26 (Android 8.0)
- **Build Tools**: 34.0.0
- **Kotlin**: 1.9.20
- **Gradle**: 8.14.3

### Dependencies
- yt-dlp: Latest stable version (embedded)
- FFmpeg: Custom build with essential codecs
- AndroidX libraries for modern UI components

## 📄 Files Included
- `StashOpusPlayer-v8.1.6-release.apk` - Production build (recommended)
- `StashOpusPlayer-v8.1.6-debug.apk` - Debug build (for development)

## ⚠️ Important Notes
- This version requires Android 8.0 (API level 26) or higher
- First launch may take longer due to yt-dlp initialization
- Ensure sufficient storage space for downloaded audio files
- Some YouTube videos may be region-restricted and unavailable

## 🔄 What's Next
- Performance optimizations based on user feedback
- Additional audio format support
- Enhanced playlist management features
- Improved offline playback capabilities

---

*For support, issues, or feature requests, please visit our GitHub repository.*

**Download Size**: ~45MB (varies by architecture)  
**License**: Open Source  
**Compatibility**: Android 8.0+
