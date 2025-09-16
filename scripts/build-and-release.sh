#!/bin/bash
#
# StashOpusPlayer - Automated Build and Release Script
# This script builds both debug and release APKs and packages them for GitHub release
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 StashOpusPlayer - Build and Release Script${NC}"
echo -e "${BLUE}================================================${NC}"

# Get version from build.gradle
VERSION=$(grep 'versionName' app/build.gradle | sed 's/.*"\(.*\)".*/\1/')
VERSION_CODE=$(grep 'versionCode' app/build.gradle | sed 's/.*\([0-9]\+\).*/\1/')

echo -e "${YELLOW}📱 Building StashOpusPlayer v$VERSION (Code: $VERSION_CODE)${NC}"

# Clean previous builds
echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
./gradlew clean

# Build debug APK
echo -e "${BLUE}🔨 Building debug APK...${NC}"
./gradlew assembleDebug

# Build release APK  
echo -e "${BLUE}🔨 Building release APK...${NC}"
./gradlew assembleRelease

# Create release directory
RELEASE_DIR="releases/v$VERSION"
echo -e "${BLUE}📁 Creating release directory: $RELEASE_DIR${NC}"
mkdir -p "$RELEASE_DIR"

# Copy APKs with proper naming
echo -e "${BLUE}📦 Packaging APKs...${NC}"
cp app/build/outputs/apk/debug/app-debug.apk "$RELEASE_DIR/StashOpusPlayer-v$VERSION-debug.apk"
cp app/build/outputs/apk/release/app-release.apk "$RELEASE_DIR/StashOpusPlayer-v$VERSION-release.apk"

# Get file sizes
DEBUG_SIZE=$(du -h "$RELEASE_DIR/StashOpusPlayer-v$VERSION-debug.apk" | cut -f1)
RELEASE_SIZE=$(du -h "$RELEASE_DIR/StashOpusPlayer-v$VERSION-release.apk" | cut -f1)

# Create release notes
echo -e "${BLUE}📝 Generating release notes...${NC}"
cat > "$RELEASE_DIR/RELEASE_NOTES.md" << EOF
# StashOpusPlayer v$VERSION Release Notes

## 🚀 Latest Version - Built on $(date)

### ✅ **Key Features**
- **Real YouTube downloads** using built-in yt-dlp + FFmpeg
- **NO demo files** - only authentic YouTube content  
- **Pending status only** - no confusing progress bars
- **Automatic thumbnails & metadata** embedding
- **Universal compatibility** on all Android devices

---

## 📱 **Download Options**

### **Debug Version** (Recommended for testing)
- **File**: \`StashOpusPlayer-v$VERSION-debug.apk\`
- **Size**: $DEBUG_SIZE
- **Features**: Full logging and debugging enabled

### **Release Version** (Production ready)  
- **File**: \`StashOpusPlayer-v$VERSION-release.apk\`
- **Size**: $RELEASE_SIZE
- **Features**: Optimized performance, minimal logging

---

## 🔧 **Installation**

1. **Enable Unknown Sources** in your Android settings
2. **Download** either the debug or release APK
3. **Install** the APK on your Android device  
4. **Enjoy** real YouTube audio downloads!

---

## 🛠️ **Technical Details**

- **Version Code**: $VERSION_CODE
- **Minimum Android**: API 21 (Android 5.0)
- **Target Android**: API 34 (Android 14)
- **Built with**: yt-dlp + FFmpeg integration
- **Size**: ~128MB (includes yt-dlp + FFmpeg libraries)

---

## 🎵 **What's New**

- Enhanced yt-dlp integration for reliable YouTube extraction
- FFmpeg processing for professional audio quality
- Automatic thumbnail downloading and embedding
- Improved error handling and retry mechanisms  
- Clean pending status without confusing progress bars

**Finally - a YouTube audio downloader that actually downloads YouTube audio!** 🎉

---

*Built automatically on $(date)*
EOF

# Create or update main releases README
echo -e "${BLUE}📄 Updating main releases README...${NC}"
cat > "releases/README.md" << EOF
# StashOpusPlayer Releases 📱

Welcome to the official releases directory for **StashOpusPlayer** - the ultimate YouTube audio downloader for Android!

## 🚀 Latest Release: v$VERSION

### **Pure yt-dlp + FFmpeg Integration - NO MORE DEMO FILES!**

- ✅ **Real YouTube downloads only** (no placeholder content)
- ✅ **Built-in yt-dlp + FFmpeg** for 100% reliability  
- ✅ **Pending status only** (no confusing progress bars)
- ✅ **Automatic thumbnails & metadata** embedding
- ✅ **Universal compatibility** (works everywhere)

**[📁 Download v$VERSION](v$VERSION/)**

---

## 📱 Quick Install

### **Option 1: Direct Download**
1. Navigate to the [latest release folder](v$VERSION/)
2. Download either:
   - **Debug APK** (recommended for testing) 
   - **Release APK** (production ready)
3. Enable "Unknown Sources" on your Android device
4. Install the APK and enjoy!

### **Option 2: ADB Install** 
\`\`\`bash
# Debug version
adb install -r releases/v$VERSION/StashOpusPlayer-v$VERSION-debug.apk

# Release version  
adb install -r releases/v$VERSION/StashOpusPlayer-v$VERSION-release.apk
\`\`\`

---

## 🎯 What Makes StashOpusPlayer Special?

### **Real YouTube Downloads**
- **No demo files** or placeholder content
- **Authentic YouTube audio** extracted using yt-dlp
- **Professional quality** processed through FFmpeg

### **Built for Reliability** 
- **Self-contained** - no external service dependencies
- **Auto-updating** yt-dlp keeps working with YouTube changes
- **Universal compatibility** - works on any device, any network

### **User-Friendly**
- **Simple interface** with clean status indicators
- **Automatic metadata** with embedded thumbnails
- **Multiple formats** - MP3, M4A, OPUS, WebM support

---

## 🔗 Links

- **Source Code**: [GitHub Repository](https://github.com/DarrylClay2005/StashOpusPlayer)
- **Issues & Support**: [GitHub Issues](https://github.com/DarrylClay2005/StashOpusPlayer/issues)
- **Latest Release**: [v$VERSION](v$VERSION/)

---

*All APK files are stored using Git LFS for reliable downloads*

*Last updated: $(date)*
EOF

# Summary
echo -e "${GREEN}✅ Build and release completed successfully!${NC}"
echo -e "${GREEN}📦 Files created:${NC}"
echo -e "   📱 Debug APK: $RELEASE_DIR/StashOpusPlayer-v$VERSION-debug.apk ($DEBUG_SIZE)"
echo -e "   📱 Release APK: $RELEASE_DIR/StashOpusPlayer-v$VERSION-release.apk ($RELEASE_SIZE)" 
echo -e "   📝 Release Notes: $RELEASE_DIR/RELEASE_NOTES.md"
echo -e "   📄 Main README: releases/README.md"

echo -e "${YELLOW}🔄 Next steps:${NC}"
echo -e "   1. Review the generated files"
echo -e "   2. Commit and push to GitHub:"
echo -e "      ${BLUE}git add releases/${NC}"
echo -e "      ${BLUE}git commit -m \"📱 Release v$VERSION APKs with Git LFS\"${NC}"
echo -e "      ${BLUE}git push origin main${NC}"
echo -e "   3. Create GitHub release tag if desired"

echo -e "${GREEN}🎉 Ready to release StashOpusPlayer v$VERSION!${NC}"
