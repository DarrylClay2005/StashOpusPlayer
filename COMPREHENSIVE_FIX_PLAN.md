# Comprehensive Fix Plan

## Issues to Fix

### 1. Purple Background Force Issue
- AppearancePreferences defaults to gray `0xFF1F2937` but something is overriding it
- Need to check:  
  - MainActivity.applyAppearanceTheme()
  - ThemeManager.applyToActivity()
  - Any theme application in onCreate

### 2. Appearance Tab Not Showing Settings
- buildAppearanceContent() returns scrollView correctly (line 2136)
- Content is added to layout properly
- Problem: likely string resources missing or appearance tab switch in onCreateView

### 3. 8D Audio Not Working
- Need to connect Functional8DAudioProcessor to ExoPlayer
- Check audio session ID propagation
- Ensure audio effects are properly initialized

### 4. Equalizer Not Tied to Audio Session
- EqualizerManager needs ExoPlayer's audio session ID
- Check MediaPlayer vs ExoPlayer connection
- Ensure audio session is passed from MusicService

### 5. Artwork Not Loading in FolderDetail
- Currently uses synchronous metadata extraction
- Problem: MetadataExtractor.extractMetadata() may not be actually loading artwork
- Need to verify artwork extraction and caching

## Fixes to Implement

1. Disable automatic theme application in MainActivity
2. Reset appearance preferences to neutral defaults
3. Connect equalizer to proper audio session ID from ExoPlayer
4. Connect 8D audio processor to ExoPlayer pipeline
5. Fix artwork extraction to use direct Glide caching
