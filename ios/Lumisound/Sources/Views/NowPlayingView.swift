import SwiftUI
import UIKit

// MARK: - Now Playing secondary-controls panel
//
// The advanced controls are grouped into switchable panels (segmented control)
// instead of one long vertical wall, so the core playback stays prominent and
// the extras are organized — the layout big music apps use.
enum NowPlayingPanel: String, CaseIterable, Identifiable {
    case controls   = "Controls"
    case sound      = "Sound"
    case queue      = "Queue"
    case lyrics     = "Lyrics"
    case bookmarks  = "Marks"
    var id: String { rawValue }
}

// MARK: - Vertical Slider

/// A vertical slider built by rotating a standard SwiftUI Slider -90 degrees.
struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            Slider(
                value: $value,
                in: range
            )
            .rotationEffect(.degrees(-90))
            .frame(width: geo.size.height, height: geo.size.width)
            .offset(
                x: (geo.size.width - geo.size.height) / 2,
                y: (geo.size.height - geo.size.width) / 2
            )
            .tint(AppTheme.dynamicAccent)
        }
    }
}

// MARK: - NowPlayingView

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayerManager
    // Deliberately NOT `@EnvironmentObject var progress: PlaybackProgress` —
    // that subscribes this view to every ~0.25-0.5s position tick regardless
    // of whether `body` reads it (see NowPlayingView+Timeline.swift's
    // isolation comment). The few pieces that need live position
    // (`NowPlayingScrubber`, `NowPlayingPlaytimeCounter`, `NowPlayingLyricsBody`)
    // declare their own `progress` subscription instead; one-shot reads
    // (adding a bookmark) use `player.position` — a plain, non-published
    // passthrough — instead.
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var sleepTimer: SleepTimerService

    // Seeking
    @State var isSeeking = false
    @State var draftPosition: TimeInterval = 0

    // Artwork pulse animation
    @State var artworkScale: CGFloat = 1.0
    @State var artworkOpacity: Double = 1.0

    // Artwork swipe-to-skip (horizontal drag on the artwork area)
    @State var artworkDragOffset: CGFloat = 0
    @State var artworkDragScale: CGFloat = 1.0

    // Track-change animation ID
    @State var artworkAnimationID: String = ""

    // Track info slide-up/fade-in animation
    @State var trackInfoVisible: Bool = true

    // Collapsible panels
    @State var showPlaybackControls = true
    @State var showABRepeat = false
    @State var showEffects = false
    @State var showEQ = true
    @State var showLyrics = false
    @State var showLyricsSyncEditor = false
    // Bumped after add/remove so the view re-reads BookmarkStore (which
    // isn't an ObservableObject — it's a plain persisted store, same shape
    // as DownloadLedgerStore/PlayHistoryStore).
    @State var bookmarksRefreshToken = UUID()

    // Artwork style selection — a String rather than `NowPlayingArtworkStyle`
    // directly, since it now needs to represent EITHER one of the 19
    // built-in cases (by rawValue) OR a user-created `CustomNowPlayingStyle`
    // (by its UUID id) — see `selectedBuiltinStyle`/`selectedCustomStyle`.
    // Falls back to the default below both for first-time users AND for
    // anyone whose saved value predates the 2026-07 visual overhaul (the
    // old case names no longer exist in any form).
    @State var artworkStyleSelection: String =
        UserDefaults.standard.string(forKey: "nowPlaying_artworkStyle") ?? NowPlayingArtworkStyle.kaleidoscopeBloom.rawValue
    @ObservedObject var customStyleStore = CustomStyleStore.shared
    @ObservedObject var hiddenStylesStore = HiddenStylesStore.shared
    @State var showCustomStyleEditor = false
    @State var editingCustomStyle: CustomNowPlayingStyle?
    @State var showStyleManager = false

    var selectedBuiltinStyle: NowPlayingArtworkStyle? {
        NowPlayingArtworkStyle(rawValue: artworkStyleSelection)
    }

    var selectedCustomStyle: CustomNowPlayingStyle? {
        customStyleStore.style(withID: artworkStyleSelection)
    }

    var visibleBuiltinStyles: [NowPlayingArtworkStyle] {
        NowPlayingArtworkStyle.allCases.filter { !hiddenStylesStore.isHidden($0.rawValue) }
    }

    /// Applies a style selection and persists it — shared by the picker
    /// chips and the "apply" action from the style manager sheet.
    func selectStyle(_ selectionID: String) {
        artworkStyleSelection = selectionID
        UserDefaults.standard.set(selectionID, forKey: "nowPlaying_artworkStyle")
        if let playlistID = player.currentPlaylistID {
            library.setPreferredArtworkStyle(selectionID, forPlaylistID: playlistID)
        }
    }

    // Seeker style
    @State var seekerStyle: SeekerStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_seekerStyle"),
           let style = SeekerStyle(rawValue: raw) {
            return style
        }
        return .waveform
    }()

    // Playtime counter style
    @State var playtimeCounterStyle: PlaytimeCounterStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_playtimeCounterStyle"),
           let style = PlaytimeCounterStyle(rawValue: raw) {
            return style
        }
        return .elapsedRemaining
    }()

    // Queue preview panel
    @AppStorage("nowPlaying_showQueuePreview") var showQueuePreview = true

    // Sleep Timer sheet
    @State var showSleepTimerSheet = false

    // Format info sheet
    @State var showFormatInfoSheet = false

    // Custom speed / pitch inline editing
    @State var editingSpeed = false
    @State var speedInput = ""
    @State var editingPitch = false
    @State var pitchInput = ""

    // Lyrics
    @State var lyricsLines: [LrcLine] = []

    // Haptic generators — created once, prepared in onAppear
    let seekHaptic = UIImpactFeedbackGenerator(style: .light)
    let playHaptic = UIImpactFeedbackGenerator(style: .light)
    let skipHaptic = UIImpactFeedbackGenerator(style: .medium)
    let heartHaptic = UIImpactFeedbackGenerator(style: .soft)
    let selectHaptic = UISelectionFeedbackGenerator()

    @State var selectedPanel: NowPlayingPanel = .controls
    @Namespace var panelPickerNamespace

    var body: some View {
        NavigationStack {
            scrollContent
                .appScreenBackground()
                .background(GalleryBackgroundView().ignoresSafeArea())
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(sleepTimer)
        }
        .sheet(isPresented: $showFormatInfoSheet) {
            FormatInfoSheet(song: player.currentSong, isUsingFallback: player.isUsingOpusPlayer)
                .environmentObject(library)
        }
        .onChange(of: player.currentSong?.id) { newID in
            guard newID != nil else { return }
            triggerTrackChangeAnimation()
            triggerTrackInfoAnimation()
            loadLyrics()
        }
        .onChange(of: player.currentPlaylistID) { playlistID in
            guard let playlistID,
                  let playlist = library.playlists.first(where: { $0.id == playlistID }),
                  let raw = playlist.preferredArtworkStyle
            else { return }
            artworkStyleSelection = raw
        }
        .onAppear {
            seekHaptic.prepare()
            playHaptic.prepare()
            skipHaptic.prepare()
            heartHaptic.prepare()
            selectHaptic.prepare()
            loadLyrics()
        }
    }


}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    let isPlaying: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            let phase = ArtworkClock.pingPong(timeline.date, legDuration: 1.8)
            content
                .scaleEffect(isPlaying ? 1.0 + 0.022 * phase : 1.0)
                .animation(.easeOut(duration: 0.4), value: isPlaying)
        }
    }
}
