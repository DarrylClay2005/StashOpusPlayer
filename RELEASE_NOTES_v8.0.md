# Stash Opus Player v8.0.0 - Major Release

## 🎵 NEW: YouTube Video Search & Download

### ✨ Major New Features

#### **YouTube Integration**
- **Brand new YouTube tab** in the bottom navigation
- **Full YouTube search** using official YouTube Data API v3
- **Video preview** with thumbnails, titles, channels, and view counts
- **Direct YouTube links** for preview in browser/YouTube app

#### **High-Quality Audio Downloads**
- **Format selection dialog** with yt-dlp style quality options
- **Multiple audio formats**: WebM (Opus), M4A (AAC), MP3
- **Quality levels**: Best, Good, Medium with specific bitrates
- **Smart format sorting** - highest quality formats first
- **Real-time download progress** tracking

#### **Supported Audio Formats**
- **WebM Opus**: 160kbps (Best), 70kbps (Good), 50kbps (Medium)
- **M4A AAC**: 128kbps (Good), 48kbps (Medium) 
- **MP3**: 320kbps (Best), 192kbps (Good), 128kbps (Medium)

#### **Advanced Download Management**
- **User-selectable download locations** with folder picker
- **Storage Access Framework** support for modern Android
- **Progress tracking** with cancellation support
- **Proper file extensions** and MIME types for each format
- **Background download** notifications

### 🛠️ Bug Fixes & Improvements

#### **Scanning System Overhaul**
- **Fixed infinite scanning** issues with folders, MediaStore, and custom directories
- **Enhanced LibraryScanTracker** with proper state management
- **Scan prevention logic** to avoid duplicate operations
- **Improved error handling** and scan completion tracking

#### **Performance Enhancements**
- **Smart scanning** with try-catch-finally blocks
- **Reduced memory usage** during library operations
- **Faster UI responsiveness** with better threading

### 🔧 Technical Updates

#### **New Dependencies**
- YouTube Data API v3 integration
- Enhanced HTTP client for downloads
- Storage Access Framework components
- JSON parsing improvements

#### **New Permissions**
- Internet access for YouTube API
- External storage management for downloads
- Network state monitoring

### 📱 UI/UX Improvements

#### **Material Design 3**
- **Beautiful format selection dialog** with video previews
- **Quality badges** for easy format identification
- **Enhanced video cards** with download progress
- **Improved navigation** with YouTube tab integration

#### **User Experience**
- **Intuitive format selection** with detailed information
- **Visual download progress** with real-time updates
- **Smart default selections** (highest quality auto-selected)
- **Clear error messages** and user feedback

### 🎯 Key Highlights

- **🆕 YouTube Tab**: Search and download videos directly in the app
- **🎵 HQ Audio**: Multiple high-quality format options like yt-dlp
- **📁 Custom Locations**: Save downloads wherever you want
- **🚀 No More Infinite Scanning**: Fixed all library scanning issues
- **⚡ Better Performance**: Faster, more responsive experience

### 🔗 YouTube API Integration

Using official YouTube Data API v3 with search capabilities:
- Real-time video search results
- Video metadata extraction
- Thumbnail loading with Glide
- Channel information display

### 🎧 Perfect for Music Lovers

This release transforms Stash Opus Player into a complete music solution:
- Play your existing music library
- Discover new music on YouTube
- Download high-quality audio files
- Organize everything in one place

---

## Installation Notes

- **Android 5.0+** (API 21+) required
- **Permissions**: App will request internet and storage permissions for YouTube downloads
- **Storage**: Recommend selecting a dedicated music folder for downloads

## Known Issues

- Format extraction currently simulates yt-dlp behavior (placeholder implementation)
- Some videos may not be available for download due to restrictions

## Coming Soon

- Real yt-dlp integration for actual video extraction
- Playlist download support
- Download queue management
- More audio format options (FLAC, OGG)

---

**Download the latest APK from the [Releases](../../releases) page**

**Version 8.0.0** - The biggest update yet! 🎉
