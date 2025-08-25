# Changelog

## 7.1.0 - 2025-08-25

- Branding: Updated About dialog and all update-related notifications to "Stash Audio"
- Android 13+: Request POST_NOTIFICATIONS permission at runtime for playback notification
- Folders: Faster folder listing using quick scan path and deferred metadata

## 7.0.0 - 2025-08-25

- Official name: Stash Audio
- Now Playing: Pitch controls are visible on all devices (scrollable controls)
- Play Store readiness: removed REQUEST_INSTALL_PACKAGES; added FOREGROUND_SERVICE_MEDIA_PLAYBACK
- Final polish and stability improvements for equalizer/pitch integration and library scanning

## 6.0.5 - 2025-08-25

- Integrated pitch semitones (-12..+12) with ExoPlayer and MediaSession commands
- Reworked Equalizer to control live playback via MediaSession (presets, bands, bass, virtualizer)
- Further speedups: fast-first song listing with background enrichment; reduced heavy metadata during scans

## 6.0.4 - 2025-08-25

- Faster initial load for Songs: fast scan shown immediately, full metadata/AI enriches in background
- Reduced heavy metadata work during scans; SAF fast scan via MediaStore when possible
- Keeps OPUS/content URI reliability and improved SAF folder grouping from prior releases

## 6.0.3 - 2025-08-25

- Persist read+write permissions for SAF trees; guidance to refresh after adding
- Folders: further tuning for SAF subfolders grouping (e.g., Internal Storage/Music/MLP)
- Songs: OPUS/content URI listing retained after rescans

## 6.0.2 - 2025-08-25

- Folders: improved SAF grouping and subfolder detection for added primary folders
- Songs: OPUS and content URI files reliably listed via resilient metadata fallback
- General: broadened audio detection for common extensions (opus, oga, mka, etc.)

## 6.0.1 - 2025-08-25

- Removed legacy loading overlay entirely
- Added Android SplashScreen on startup (500ms); simplified startup flow
- Minor cleanup and stability improvements

## 6.0.0 - 2025-08-25

- Major stability pass: removed deprecated APIs, improved lifecycle collection with repeatOnLifecycle
- Polished loading and folder refresh UX; Folders tab supports pull-to-refresh
- AI artist/genre tagging refined and integrated into repository flow
- Release artifacts: APK and AAB

## 5.0.5 - 2025-08-25

- Fixed: Folders tab now shows added folder tree directories (SAF) and supports pull-to-refresh
- New: Informative loading screen with live progress (library scan, AI tagging, image downloads)
- New: AI auto-assignment for Artist and Genre
  - Heuristic filename/folder parsing for artists
  - Last.fm tag fetch for genres when API key is provided (optional)
- Improved: Artists and Genres tabs reflect AI-enhanced metadata
- Misc: Minor UI polish, download banner for image fetch activity

# Changelog

## Version 5.3.0 (2025-08-25)

### Added
- Folder drill-down: tap a folder in Folders to view all its songs and play them.
- Artist and genre hero images with online fetching (Last.fm optional + Wikipedia fallback) and Settings toggles/API key.
- Background rescan toggle placeholder (preparing for scheduled rescans).

---

## Version 5.2.0 (2025-08-25)

### Added
- Artist/Genre images (Last.fm + Wikipedia), settings toggles & API key.

---

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
