# Changelog

## Version 5.1.1 (2025-08-25)

### Fixed
- Infinite loading overlay when permission is denied; the overlay now dismisses when falling back to Settings.

---

## Version 5.1.0 (2025-08-25)

### Added
- Genres tab now uses smart genre grouping (tags + heuristics) to better organize tracks.
- Manage Folders in Settings to view/remove selected tree URIs.
- Clear Artwork Cache button in Settings.

---

## Version 5.0.5 (2025-08-25)

### Fixed
- Folders tab now shows folders from added SAF tree directories (content://), with proper relative paths.

### Added
- Loading screen overlay during initial scan with helpful tips.
- Basic AI normalization for artists; improved grouping.
- Smart genre grouping using tag/heuristic inference API in repository.

---

## Version 5.0.2 (2025-08-25)

### Added
- Music folder picker (Storage Access Framework). Selected folders are scanned recursively, including subfolders, and appear in the Folders tab.
- Improved artwork display in lists: uses cached/online album art when embedded art is missing.

### Notes
- You can add folders from Settings -> Music Folders -> Add Folder (tree).

---

## Version 5.0.1 (2025-08-25)

### Added
- Online album artwork fetching when embedded art is missing
  - Providers: MusicBrainz + Cover Art Archive (primary), iTunes Search (fallback)
  - On-device cache with deterministic keys and downsampled loads
  - Settings toggle: Settings -> Album Artwork -> "Fetch album art online when missing"
  - Notification large icon now uses cached artwork when available

### Changed
- Minor dependency tidy (deduplicated Gson)
- Updated User-Agent for external requests

---

## Version 2.0 (2025-08-25)

### 🔧 **Fixed**
- **Installation Issues**: Fixed "app not installed because of invalid package" error
- **Modern Android Compatibility**: Updated manifest with proper backup rules and permissions
- **Deprecated API**: Replaced deprecated `onBackPressed()` with modern `OnBackPressedCallback`
- **Permission Handling**: Improved Android 13+ permission compatibility

### 🎨 **Updated**
- **New App Icon**: Professional multimedia audio player icon
- **Build Configuration**: Disabled problematic minification for better compatibility
- **Manifest Updates**: Added proper data extraction and backup rules for Android 12+

### 📱 **Technical Improvements**
- Version code: 2
- Better Android version compatibility (API 21-34)
- Improved build stability
- Enhanced installation success rate

### 📦 **APK Sizes**
- **Release APK**: 8.1MB (optimized for stability)
- **Debug APK**: 10MB (with debugging symbols)

---

## Version 1.0 (2025-08-24)

### 🎵 **Initial Release Features**
- Multi-format audio support (Opus, MP3, FLAC, OGG, M4A, WAV, AAC, WMA)
- Custom background images
- Material Design 3 UI with dark theme
- Side navigation drawer
- ExoPlayer integration
- Smart permissions handling
- Optimized performance
