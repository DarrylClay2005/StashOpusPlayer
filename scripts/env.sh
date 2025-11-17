#!/bin/bash
# Environment setup script - forces all operations to external drive
export EXTERNAL_BASE="/run/media/desmond/Steam_Recordings"
export PROJECT_ROOT="$EXTERNAL_BASE/StashOpusPlayer"
export BACKUP_ROOT="$EXTERNAL_BASE/StashOpusPlayer_V2_Systems_Backup/20251026_225924"

# Java and Android
export JAVA_HOME="$EXTERNAL_BASE/jdk-17"
export ANDROID_HOME="$EXTERNAL_BASE/android-sdk"
export ANDROID_USER_HOME="$EXTERNAL_BASE/.android"
export ANDROID_SDK_ROOT="$EXTERNAL_BASE/android-sdk"

# Gradle
export GRADLE_HOME="$EXTERNAL_BASE/gradle-8.14.3"
export GRADLE_USER_HOME="$EXTERNAL_BASE/.gradle_tmp"

# Temp directories
export TMPDIR="$EXTERNAL_BASE/tmp"
export TEMP="$EXTERNAL_BASE/tmp"
export TMP="$EXTERNAL_BASE/tmp"
export XDG_CACHE_HOME="$EXTERNAL_BASE/.cache"

# Java options to force temp to external drive
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$EXTERNAL_BASE/tmp -Duser.home=$EXTERNAL_BASE"

# Path
export PATH="$GRADLE_HOME/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

echo "✓ Environment configured for external drive: $EXTERNAL_BASE"
