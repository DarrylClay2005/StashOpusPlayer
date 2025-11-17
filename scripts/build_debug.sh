# Debug build commands (run from project root on external drive)

# Ensure temp dir exists for Gradle (fixes the IOException you saw)
mkdir -p /run/media/desmond/Steam_Recordings/tmp
export TMPDIR=/run/media/desmond/Steam_Recordings/tmp

# Run debug assemble
./gradlew assembleDebug --no-daemon --stacktrace

# If you prefer using system temp and want to unset TMPDIR later:
# unset TMPDIR
