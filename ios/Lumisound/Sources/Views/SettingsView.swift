import MediaPlayer
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Dependencies

    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var sleepTimer: SleepTimerService
    @EnvironmentObject var updater: UpdateService
    @EnvironmentObject var streaming: StreamingService
    @EnvironmentObject var account: AccountService
    @EnvironmentObject var cacheManager: CacheManagerService
    @EnvironmentObject var folderService: MusicFolderService
    @EnvironmentObject var appLock: AppLockService
    @EnvironmentObject var silenceTrim: SilenceTrimService

    /// Drives the Notifications entry row's status pill (On/Off/Needs Access)
    /// and the master toggle inside `NotificationsSettingsView`.
    @ObservedObject var notificationService = NotificationService.shared

    @State var showLogin = false

    /// Shared with `ContentView`, which hides the floating Car Mode button and
    /// disables auto-activation on car-stereo connection when this is off.
    @AppStorage("carModeEnabled") var carModeEnabled: Bool = false
    /// Shared with `CustomTabBar`/`MiniPlayerBar`/Now Playing's own toggle —
    /// see `NavbarDisplayMode`'s doc comment.
    @AppStorage("navbarDisplayMode") var navbarDisplayMode: NavbarDisplayMode = .tabs
    /// Tab-bar-mode customization — see `NavbarSelectionStyle`'s doc comment.
    @AppStorage("navbarShowTabLabels") var navbarShowTabLabels: Bool = true
    @AppStorage("navbarSelectionStyle") var navbarSelectionStyle: NavbarSelectionStyle = .glassPill
    @AppStorage("wifiOnlyDownloads.enabled") var wifiOnlyDownloadsEnabled: Bool = false

    /// When on, downloads ask the bridge to use aria2 (multi-connection) as the
    /// yt-dlp downloader. Default OFF: benchmarking showed the native downloader
    /// is ~2-3x faster than aria2 on YouTube's CDN for this deployment (aria2's
    /// many-connection splitting added overhead instead of bypassing throttling).
    /// Kept as an opt-in for networks where YouTube hard-throttles single
    /// connections, where aria2 can genuinely win. Read by
    /// `StreamingService.downloadToLibrary` and sent as `use_aria2` to the bridge.
    @AppStorage("ytdlp_use_aria2") var ytdlpUseAria2: Bool = false
    /// Optional custom subfolder for downloads (Settings → yt-dlp). When set,
    /// downloads land in "Imported Music/<folder>". Read by
    /// `StreamingService.downloadDirectory`.
    @AppStorage("ytdlp_download_folder") var ytdlpDownloadFolder: String = ""
    /// Inter-request throttle (yt-dlp --sleep-interval). 0 = fastest. Default 5.
    @AppStorage("ytdlp_throttle_seconds") var ytdlpThrottleSeconds: Int = 5
    /// Parallel DASH fragments (yt-dlp -N). Bridge default is 4 (was 1) — a
    /// meaningful download speedup for fragmented/DASH audio at negligible
    /// memory cost. Matches the bridge's own Query(8, ...) default in
    /// /api/download so the displayed value here is honest about what
    /// actually happens when this is left untouched.
    @AppStorage("ytdlp_concurrent_fragments") var ytdlpConcurrentFragments: Int = 8

    // MARK: YouTube API Key Validation / Exposure Check State

    @State var youtubeKeyConfig: YoutubeApiKeyConfig?
    @State var youtubeKeyInput = ""
    @State var isValidatingYouTubeKey = false
    @State var isSavingYouTubeKey = false
    @State var youtubeExposureTimer: Timer?

    /// Once a configured key is rejected for quota, re-show the "Set Key"
    /// field so the user can replace it. Persisted so it survives app
    /// relaunches until a new/working key is saved or validates again.
    @AppStorage("youtube_api_key_quota_exceeded") var youtubeKeyQuotaExceeded = false

    // MARK: AcoustID API Key State

    @State var acoustIDKeyConfig: AcoustIDApiKeyConfig?
    @State var acoustIDKeyInput = ""
    @State var isSavingAcoustIDKey = false

    // MARK: Streaming & Downloads state (used by streamingDownloadsSection,
    // which lives in SettingsView+StreamingDownloadsSection.swift — kept here
    // since extensions in other files can't hold stored properties)

    @State var showHealthResult = false
    @State var healthOK = false

    // MARK: Body

    /// Top-level Settings categories — replaces the old single cluttered
    /// scroll with focused tabs, each showing only its related sections.
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio"
        case library = "Library"
        case ytdlp = "yt-dlp"
        case app = "App"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "person.crop.circle"
            case .audio:   return "waveform"
            case .library: return "music.note.list"
            case .ytdlp:   return "arrow.down.circle"
            case .app:     return "gearshape"
            }
        }

        /// Each tab gets its own color (matching the icon/tint its member
        /// sections use in `sectionHeader`) instead of every tab sharing one
        /// flat accent — part of the same "settings' categories should read
        /// as visually distinct at a glance" redesign as the section headers.
        var tint: Color {
            switch self {
            case .general: return .blue
            case .audio:   return .teal
            case .library: return .pink
            case .ytdlp:   return .yellow
            case .app:     return .green
            }
        }
    }

    @State var selectedTab: SettingsTab = .general
    /// Drives the tab picker's sliding selection background — see `tabPicker`.
    @Namespace private var tabIndicatorNamespace

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                List {
                    // Update banner — visible on every tab when an update is available.
                    if updater.updateAvailable {
                        Section {
                            UpdateBannerView()
                                .environmentObject(updater)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    switch selectedTab {
                    case .general:
                        accountSection
                        notificationsSection
                        appearanceSection
                        sleepTimerSection
                        appLockSection
                    case .audio:
                        playbackAudioSection
                        carModeSection
                    case .library:
                        librarySection
                        streamingDownloadsSection
                    case .ytdlp:
                        ytdlpSection
                    case .app:
                        updatesSection
                        helpSection
                        aboutSection
                    }
                }
                // Cross-fade + slight vertical shift between tabs, keyed on
                // the tab itself, so switching feels like a deliberate
                // transition rather than the section list just snapping to
                // different content underneath the (already-animated) picker.
                .id(selectedTab)
                .transition(.opacity.combined(with: .move(edge: .top)))
                // Without an explicit style this defaults to a grouped-card
                // look — every Section (account/appearance/sleep timer/etc.)
                // floats as its own separate box with the gallery background
                // showing fully through the gaps. `.plain` still renders
                // Section headers as inline labels, just without each one
                // becoming a disconnected card — matches every other screen's
                // continuous-surface look.
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(account)
            }
            .task {
                await refreshYouTubeKeyStatus()
                startYouTubeExposureMonitor()
                await refreshAcoustIDKeyStatus()
            }
            .onDisappear {
                youtubeExposureTimer?.invalidate()
                youtubeExposureTimer = nil
            }
        }
    }

    /// Horizontal, scrollable category selector pinned under the title.
    /// Redesigned: each tab carries its own color (`SettingsTab.tint`) that
    /// tints its icon even while unselected, and the selected pill's
    /// background slides between tabs via `matchedGeometryEffect` (one
    /// shared shape sliding to a new position) instead of each button
    /// independently swapping its own fill color — a more deliberate,
    /// "designed" transition than a flat capsule popping in and out.
    var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedTab = tab }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .white : tab.tint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(tab.tint.gradient)
                                        .matchedGeometryEffect(id: "settingsTabIndicator", in: tabIndicatorNamespace)
                                } else {
                                    Capsule()
                                        .fill(tab.tint.opacity(0.14))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

}
