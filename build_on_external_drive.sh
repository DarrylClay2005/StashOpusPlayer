#!/bin/bash

# Stash Opus Player - External Drive Build Script
# Ensures all build operations use the external hard drive to avoid Live USB space issues

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Stash Opus Player - External Drive Build${NC}"
echo "========================================"

# Define external drive path
EXTERNAL_DRIVE="/run/media/liveuser/Steam_Recordings"
PROJECT_DIR="$EXTERNAL_DRIVE/StashOpusPlayer"

# Ensure we're in the project directory
cd "$PROJECT_DIR"

echo -e "${YELLOW}📂 Configuring build environment for external drive...${NC}"

# Create all necessary directories on external drive
mkdir -p "$EXTERNAL_DRIVE/tmp"
mkdir -p "$EXTERNAL_DRIVE/.gradle"
mkdir -p "$EXTERNAL_DRIVE/.android"
mkdir -p "$EXTERNAL_DRIVE/.m2"
mkdir -p "$EXTERNAL_DRIVE/build-cache"

# Set all environment variables to use external drive
export TMPDIR="$EXTERNAL_DRIVE/tmp"
export TMP="$EXTERNAL_DRIVE/tmp"
export TEMP="$EXTERNAL_DRIVE/tmp"
export ANDROID_HOME="$EXTERNAL_DRIVE/android-sdk"
export GRADLE_USER_HOME="$EXTERNAL_DRIVE/.gradle"
export ANDROID_USER_HOME="$EXTERNAL_DRIVE/.android"
export M2_HOME="$EXTERNAL_DRIVE/.m2"
export MAVEN_OPTS="-Djava.io.tmpdir=$EXTERNAL_DRIVE/tmp"
export JAVA_OPTS="-Djava.io.tmpdir=$EXTERNAL_DRIVE/tmp -Dorg.sqlite.tmpdir=$EXTERNAL_DRIVE/tmp"

# Configure Gradle to use external drive for all operations
export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx4g \
-Djava.io.tmpdir=$EXTERNAL_DRIVE/tmp \
-Dorg.sqlite.tmpdir=$EXTERNAL_DRIVE/tmp \
-Dgradle.user.home=$EXTERNAL_DRIVE/.gradle \
--add-opens=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.comp=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \
--add-opens=jdk.compiler/com.sun.tools.javac.model=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.comp=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \
--add-exports=jdk.compiler/com.sun.tools.javac.model=ALL-UNNAMED"

echo -e "${GREEN}✓ Environment configured for external drive${NC}"
echo "  - TMPDIR: $TMPDIR"
echo "  - ANDROID_HOME: $ANDROID_HOME"
echo "  - GRADLE_USER_HOME: $GRADLE_USER_HOME"

# Verify space available on external drive
AVAILABLE_SPACE=$(df -h "$EXTERNAL_DRIVE" | awk 'NR==2 {print $4}')
echo -e "${BLUE}💾 Available space on external drive: $AVAILABLE_SPACE${NC}"

# Clean any existing build artifacts
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
./gradlew clean --no-daemon --stacktrace || true

# Display Java version
echo -e "${BLUE}☕ Java version:${NC}"
java -version

# Build release APK and AAB
echo -e "${YELLOW}🔨 Building release APK and AAB...${NC}"
echo "Starting build process..."

# First, try assembleRelease
if ./gradlew assembleRelease --no-daemon --stacktrace --info; then
    echo -e "${GREEN}✓ Release APK built successfully!${NC}"
    APK_PATH=$(find app/build/outputs/apk/release -name "*.apk" | head -1)
    if [ -n "$APK_PATH" ]; then
        echo -e "${GREEN}📱 APK Location: $APK_PATH${NC}"
        ls -lh "$APK_PATH"
    fi
else
    echo -e "${RED}❌ Release APK build failed${NC}"
    echo "Trying debug build as fallback..."
    
    if ./gradlew assembleDebug --no-daemon --stacktrace; then
        echo -e "${YELLOW}✓ Debug APK built successfully as fallback!${NC}"
        DEBUG_APK_PATH=$(find app/build/outputs/apk/debug -name "*.apk" | head -1)
        if [ -n "$DEBUG_APK_PATH" ]; then
            echo -e "${YELLOW}📱 Debug APK Location: $DEBUG_APK_PATH${NC}"
            ls -lh "$DEBUG_APK_PATH"
        fi
    else
        echo -e "${RED}❌ Both release and debug builds failed${NC}"
        exit 1
    fi
fi

# Try to build AAB if release APK succeeded
if [ -f "$APK_PATH" ]; then
    echo -e "${YELLOW}📦 Building Android App Bundle (AAB)...${NC}"
    if ./gradlew bundleRelease --no-daemon --stacktrace; then
        echo -e "${GREEN}✓ Release AAB built successfully!${NC}"
        AAB_PATH=$(find app/build/outputs/bundle/release -name "*.aab" | head -1)
        if [ -n "$AAB_PATH" ]; then
            echo -e "${GREEN}📦 AAB Location: $AAB_PATH${NC}"
            ls -lh "$AAB_PATH"
        fi
    else
        echo -e "${YELLOW}⚠ AAB build failed, but APK is available${NC}"
    fi
fi

# Summary
echo -e "${BLUE}🎉 Build Summary${NC}"
echo "================"
if [ -n "$APK_PATH" ]; then
    echo -e "${GREEN}✓ Release APK: Built successfully${NC}"
elif [ -n "$DEBUG_APK_PATH" ]; then
    echo -e "${YELLOW}✓ Debug APK: Built successfully (fallback)${NC}"
fi

if [ -n "$AAB_PATH" ]; then
    echo -e "${GREEN}✓ Release AAB: Built successfully${NC}"
fi

echo -e "${BLUE}All build artifacts are stored on the external drive in:${NC}"
echo "  - APKs: app/build/outputs/apk/"
echo "  - AABs: app/build/outputs/bundle/"
echo "  - Build cache: $EXTERNAL_DRIVE/.gradle"

df -h "$EXTERNAL_DRIVE" | tail -1