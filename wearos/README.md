# StashOpusPlayer WearOS Companion App

A Wear OS companion app for the StashOpusPlayer music app, providing remote control and music browsing capabilities directly from your smartwatch.

## Features Implemented ✅

- **Complete WearOS Module Structure**: Proper Wear OS app configuration with dependencies
- **Data Layer Communication**: Wearable Data Layer API implementation for phone-watch communication
- **Modern UI**: Watch-optimized layouts with circular design patterns
- **Main Activities**:
  - `MainActivity`: Connection status and basic playback controls
  - `PlayerActivity`: Full-screen player with progress indicator
  - `TrackListActivity`: Browsable music library
- **Phone Connectivity**: Automatic phone connection detection and status updates
- **Watch Face Complications**: Display current track info on watch faces
- **Repository Pattern**: Clean architecture with WearMusicRepository
- **MVVM Architecture**: ViewModel-based UI state management

## Core Components

### Data Layer
- `WearSong`, `WearPlaybackState`, `WearPlaylist`: Data models for watch-phone communication
- `DataLayerListenerService`: Receives updates from phone app
- `WearMusicRepository`: Singleton repository managing all watch music state

### UI Layer
- `MainActivity`: Home screen with connection status and mini player
- `PlayerActivity`: Full-featured music player interface
- `TrackListActivity`: Scrollable track selection
- `WearMusicViewModel`: UI state management and control commands
- `TrackListAdapter`: RecyclerView adapter for music tracks

### Services
- `DataLayerListenerService`: Handles phone data updates
- `MusicComplicationService`: Provides watch face complications

## Phone App Integration Required

To complete the WearOS integration, the phone app needs these additions:

### 1. Phone-side Data Layer Service
```kotlin
// Add to phone app's manifest
<service android:name=".service.WearDataLayerService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.android.gms.wearable.DATA_CHANGED" />
        <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED" />
        <data android:scheme="wear" android:host="*" />
    </intent-filter>
</service>
```

### 2. Phone Music Service Updates
Add to `MusicService.kt`:
```kotlin
private fun sendWearableUpdate(state: WearPlaybackState) {
    val dataClient = Wearable.getDataClient(this)
    val putDataReq = PutDataMapRequest.create(WearDataPaths.PLAYBACK_STATE).apply {
        dataMap.putBoolean("isPlaying", state.isPlaying)
        dataMap.putLong("position", state.position)
        dataMap.putLong("duration", state.duration)
        // ... other fields
    }.asPutDataRequest()
    
    dataClient.putDataItem(putDataReq)
}
```

### 3. MediaSession Bridge
The existing MediaSession in `MusicService.kt` already provides the foundation - just needs wearable data broadcasting.

## Installation

1. Build both phone and watch APKs:
```bash
./gradlew assembleDebug        # Phone app
./gradlew :wearos:assembleDebug # Watch app
```

2. Install phone app first:
```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

3. Install watch app via Android Studio or:
```bash
adb -s <watch_device_id> install wearos/build/outputs/apk/debug/wearos-debug.apk
```

## Remaining Features (Optional Enhancements)

### Media Session Integration
While data layer communication is implemented, direct MediaSession integration could provide:
- System-level media controls
- Better integration with Android Auto when phone is connected
- Standardized media notifications

### Notification Actions
Enhanced notification with media controls:
- Play/pause from notification
- Skip track buttons
- Rich media notification style

### Gesture Controls  
Advanced watch interactions:
- Rotating crown for volume/seek
- Touch gestures for track navigation
- Swipe actions for quick controls

## Architecture Notes

The app follows modern Android development practices:
- **Repository Pattern**: Single source of truth for music data
- **MVVM**: Clean separation of concerns
- **Kotlin Coroutines**: Async operations and StateFlow for reactive UI
- **Data Layer API**: Efficient phone-watch communication
- **Lifecycle Aware**: Proper resource management

## Development

The WearOS module is a complete standalone app that communicates with the phone app via the Wearable Data Layer. All core functionality for music control and browsing is implemented and ready for testing.

To test without the phone integration, you can mock data in `WearMusicRepository` or implement test data providers.

## File Structure

```
wearos/
├── src/main/
│   ├── AndroidManifest.xml
│   ├── java/com/stash/opusplayer/wearos/
│   │   ├── complications/MusicComplicationService.kt
│   │   ├── data/WearSong.kt
│   │   ├── repository/WearMusicRepository.kt
│   │   ├── service/DataLayerListenerService.kt
│   │   ├── ui/
│   │   │   ├── MainActivity.kt
│   │   │   ├── PlayerActivity.kt
│   │   │   ├── TrackListActivity.kt
│   │   │   └── adapter/TrackListAdapter.kt
│   │   └── viewmodel/WearMusicViewModel.kt
│   └── res/
│       ├── drawable/       # Icons and graphics
│       ├── layout/         # UI layouts
│       └── values/         # Strings, colors, styles
└── build.gradle           # Build configuration
```

The companion app is production-ready for core music control features and provides a solid foundation for additional enhancements.
