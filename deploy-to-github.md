# Deploy to GitHub Instructions

This document contains instructions for deploying the Stash Opus Player to GitHub.

## Step 1: Create GitHub Repository

Using GitHub CLI (if authenticated):
```bash
gh repo create StashOpusPlayer --public --description "A visually appealing Android music player with support for Opus and other audio formats"
```

Or manually:
1. Go to https://github.com
2. Click "New repository"
3. Name: `StashOpusPlayer`
4. Description: `A visually appealing Android music player with support for Opus and other audio formats`
5. Public repository
6. Don't initialize with README (we already have one)

## Step 2: Push Code to GitHub

```bash
# Add remote origin
git remote add origin https://github.com/[YOUR_USERNAME]/StashOpusPlayer.git

# Push code
git branch -M main
git push -u origin main
```

## Step 3: Create Release

### Using GitHub CLI:
```bash
# Create a release with APK files
gh release create v1.0.0 \
    releases/stash-opus-player-debug.apk \
    releases/stash-opus-player-release.apk \
    --title "Stash Opus Player v1.0.0" \
    --notes "Initial release with multi-format audio support, custom backgrounds, and Material Design 3 UI"
```

### Manual Release:
1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Tag: `v1.0.0`
4. Title: `Stash Opus Player v1.0.0`
5. Description:
```
# Stash Opus Player v1.0.0

## Features
- Multi-format audio support (Opus, MP3, FLAC, OGG, M4A, WAV, AAC, WMA)
- Custom background image support
- Material Design 3 UI with dark theme
- Side navigation drawer
- Smart permissions handling
- Optimized ~4MB APK size

## Downloads
- **stash-opus-player-release.apk** - Optimized release build (4.1MB)
- **stash-opus-player-debug.apk** - Debug build with additional logging (10MB)

## Installation
1. Download the release APK
2. Enable "Unknown Sources" in Android settings
3. Install the APK
4. Grant audio permissions when prompted

## Requirements
- Android 5.0+ (API Level 21+)
- ~10MB storage space
```
6. Attach the APK files from the `releases/` folder
7. Click "Publish release"

## Repository Structure
```
StashOpusPlayer/
├── app/                    # Main application module
├── gradle/                 # Gradle wrapper files
├── releases/               # Pre-built APK files
├── .gitignore             # Git ignore rules
├── README.md              # Project documentation
├── LICENSE                # MIT License
└── build.gradle           # Root build configuration
```
