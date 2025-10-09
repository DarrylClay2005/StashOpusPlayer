# Changelog for v13.2.1

## Summary
- Fix: Gradle repository URL assignment to be compatible with Gradle 8 and future Gradle 10 changes
- Build: Added helper script to build to Steam_Recordings external drive and redirect Gradle caches/outputs
- Build: Verified debug and release builds succeed with outputs on external drive
- Meta: Bumped app version to 13.2.1 (versionCode 146)

## Details
- settings.gradle: use `maven { url = 'https://jitpack.io' }`
- build.gradle (top-level): use `maven { url = 'https://jitpack.io' }` in buildscript and allprojects
- scripts/build_to_steam_recordings.sh: added to streamline builds on external drive
- app/build.gradle: versionCode 146, versionName 13.2.1

Artifacts built on external drive:
- Debug APK: /run/media/liveuser/Steam_Recordings/StashOpusPlayer-build/app/outputs/apk/debug/app-debug.apk
- Release APK: /run/media/liveuser/Steam_Recordings/StashOpusPlayer-build/app/outputs/apk/release/app-release.apk
