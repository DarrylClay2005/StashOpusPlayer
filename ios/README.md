# Stash Opus Player for iOS

This is the native iOS rebuild of the Android `StashOpusPlayer` project. The Android app remains intact in `app/`; this folder is the new SwiftUI/AVFoundation app that will become the IPA target.

## Current Foundation

- SwiftUI app shell with Library, Now Playing, Queue, and Settings tabs.
- AVFoundation playback manager with queue, repeat, shuffle, speed, pitch, volume, and a 10-band EQ surface.
- Media library scanner using `MPMediaLibrary` and imported-file support using the iOS document picker.
- Core models ported from the Android app: song, playlist, playback state, audio settings.
- Background audio and Now Playing / remote control wiring.

## Generate the Xcode Project

On macOS:

```sh
cd ios
brew install xcodegen
xcodegen generate
open StashOpusPlayer.xcodeproj
```

Set your Apple development team in Xcode before archiving.

## Build an IPA

```sh
cd ios
./scripts/build-ipa.sh
```

The script requires macOS with Xcode command line tools, XcodeGen, and a valid signing team/profile.
