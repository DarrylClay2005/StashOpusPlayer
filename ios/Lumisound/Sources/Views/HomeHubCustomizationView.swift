import SwiftUI

// MARK: - Home Hub customization
//
// Three device-local personalization knobs for `LibraryHubView`'s dashboard:
// section reordering/visibility, a custom greeting override, and a
// Home-only accent color. All three are plain per-device UI preferences —
// like `tab_transition_style` in `ContentView` — persisted via
// `@AppStorage`/`UserDefaults`, never server-synced. None of this touches
// the profile/social accent system in `Views/Social/ProfileView.swift`;
// it reuses `AccentColorPickerView`/`SocialAccentPalette` purely as UI/color
// components, with entirely separate storage keys.

// MARK: - Section identifiers

/// Every reorderable/hideable content shelf in `LibraryHubView.hubContent`
/// — everything except the greeting header and quick-actions row, which are
/// pinned identity/action anchors rather than content shelves and stay fixed
/// at the top always.
enum HubSectionKind: String, CaseIterable, Codable, Identifiable {
    case onThisDay
    case speedDial
    case weeklyMix
    case mixes
    case recentlyAdded
    case onRepeat
    case recentlyPlayed
    case genres
    case forgottenFavorites
    case moods
    case friendsActivity
    case similarListeners
    // 2026-07-20 Home Tab expansion — see `LibraryHubView`'s corresponding
    // `sectionContent`/`sectionHasContent` cases and `LibraryManager+HubContent.swift`
    // for each one's data source.
    case achievements
    case weeklyRecap
    case topArtists
    case decades
    case deeperCuts
    // 2026-08 Podcasts — in-progress episodes across every subscription,
    // same "teaser card, not reorderable-carousel" shape as onThisDay.
    case continueListeningPodcasts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onThisDay:          return "On This Day"
        case .speedDial:          return "Quick Access"
        case .weeklyMix:          return "Weekly Mix"
        case .mixes:              return "Mixes For You"
        case .recentlyAdded:      return "Recently Added"
        case .onRepeat:           return "On Repeat"
        case .recentlyPlayed:     return "Recently Played"
        case .genres:             return "Genres"
        case .forgottenFavorites: return "Forgotten Favorites"
        case .moods:              return "Moods"
        case .friendsActivity:    return "Friends Activity"
        case .similarListeners:   return "Similar Listeners"
        case .achievements:       return "Streaks & Achievements"
        case .weeklyRecap:        return "This Week"
        case .topArtists:         return "Top Artists"
        case .decades:            return "Decades"
        case .deeperCuts:         return "Deeper Cuts"
        case .continueListeningPodcasts: return "Continue Listening"
        }
    }

    /// Matches the icon each section already uses in its own header today —
    /// kept in sync by hand since these live as string literals at each
    /// `HubSectionHeader(...)` call site in `LibraryHubView.swift`.
    var icon: String {
        switch self {
        case .onThisDay:          return "clock.arrow.circlepath"
        case .speedDial:          return "square.grid.2x2.fill"
        case .weeklyMix:          return "sparkles.tv"
        case .mixes:              return "wand.and.stars"
        case .recentlyAdded:      return "clock.badge.checkmark"
        case .onRepeat:           return "flame.fill"
        case .recentlyPlayed:     return "clock.arrow.circlepath"
        case .genres:             return "guitars.fill"
        case .forgottenFavorites: return "heart.slash"
        case .moods:              return "theatermasks.fill"
        case .friendsActivity:    return "person.2.wave.2.fill"
        case .similarListeners:   return "person.3.sequence.fill"
        case .achievements:       return "trophy.fill"
        case .weeklyRecap:        return "chart.bar.fill"
        case .topArtists:         return "music.mic"
        case .decades:            return "hourglass"
        case .deeperCuts:         return "waveform.badge.magnifyingglass"
        case .continueListeningPodcasts: return "headphones"
        }
    }

    /// The hub's original hardcoded sequence, preserved as the default so a
    /// user who never opens the customization sheet sees exactly the same
    /// layout as before this feature existed. New 2026-07-20 sections are
    /// interleaved into sensible spots rather than only appended, so a
    /// first-run user (no saved order yet) sees them somewhere natural
    /// rather than all dumped at the very end.
    static let defaultOrder: [HubSectionKind] = [
        .onThisDay, .continueListeningPodcasts, .achievements, .weeklyRecap, .speedDial, .weeklyMix, .mixes,
        .recentlyAdded, .onRepeat, .recentlyPlayed, .topArtists, .genres, .decades,
        .forgottenFavorites, .deeperCuts, .moods, .friendsActivity, .similarListeners,
    ]
}

// MARK: - Persistence

/// JSON-encoded-array-in-`UserDefaults` storage for the hub's order/hidden
/// preferences — the same convention as every other simple per-device list
/// preference in this codebase (see e.g. `BookmarkStore`), just small enough
/// here that a dedicated store type isn't warranted; these are plain static
/// helpers around the two `@AppStorage` string keys used directly by both
/// `LibraryHubView` (to read) and `HomeHubCustomizationView` (to read+write).
enum HomeHubLayoutStore {
    static let orderKey = "home_hub_section_order"
    static let hiddenKey = "home_hub_hidden_sections"

    /// Decodes the persisted order, silently falling back to
    /// `HubSectionKind.defaultOrder` for a first run or corrupted value.
    /// Also reconciles against the current `HubSectionKind` case list both
    /// ways: unknown/stale raw values (e.g. a section removed in a later
    /// update) are dropped, and any *new* case missing from an older saved
    /// order is appended at the end rather than silently never appearing.
    static func decodeOrder(_ json: String) -> [HubSectionKind] {
        var seen = Set<HubSectionKind>()
        var result: [HubSectionKind] = []
        if let data = json.data(using: .utf8),
           let raw = try? JSONDecoder().decode([String].self, from: data) {
            for value in raw {
                guard let kind = HubSectionKind(rawValue: value), seen.insert(kind).inserted else { continue }
                result.append(kind)
            }
        }
        for kind in HubSectionKind.defaultOrder where !seen.contains(kind) {
            result.append(kind)
            seen.insert(kind)
        }
        return result
    }

    static func encodeOrder(_ order: [HubSectionKind]) -> String {
        encode(order.map { $0.rawValue })
    }

    static func decodeHidden(_ json: String) -> Set<HubSectionKind> {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(raw.compactMap { HubSectionKind(rawValue: $0) })
    }

    static func encodeHidden(_ hidden: Set<HubSectionKind>) -> String {
        encode(hidden.map { $0.rawValue })
    }

    private static func encode(_ rawValues: [String]) -> String {
        guard let data = try? JSONEncoder().encode(rawValues),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

// MARK: - Customization sheet

/// The hub's "Edit" sheet — reorder/show/hide sections, set a custom
/// greeting, and pick a Home-only accent color. A plain `List` forced into
/// edit mode with `.onMove` rather than hand-rolled drag gestures, since
/// this machine has no local Swift toolchain to compile-test a custom
/// implementation against — `.onMove`/`.environment(\.editMode:)` is a
/// standard, well-trodden SwiftUI pattern that doesn't need that safety net.
struct HomeHubCustomizationView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(HomeHubLayoutStore.orderKey) private var orderRaw: String = ""
    @AppStorage(HomeHubLayoutStore.hiddenKey) private var hiddenRaw: String = ""
    @AppStorage("home_hub_custom_greeting") private var customGreeting: String = ""
    @AppStorage("home_hub_accent_hex") private var accentHex: String?

    @State private var order: [HubSectionKind] = []
    @State private var hidden: Set<HubSectionKind> = []

    private var accentColor: Color {
        SocialAccentPalette.color(for: accentHex) ?? AppTheme.dynamicAccent
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("e.g. \"Welcome back\"", text: $customGreeting, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Custom Greeting")
                } footer: {
                    Text("Replaces the automatic \"Good morning/afternoon/evening\" greeting on Home. Clear it to restore the automatic greeting.")
                }

                Section {
                    AccentColorPickerView(title: "Home Accent", selectedHex: $accentHex)
                        .padding(.vertical, 6)
                    if accentHex != nil {
                        Button(role: .destructive) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                accentHex = nil
                            }
                        } label: {
                            Text("Reset to Default")
                        }
                    }
                } header: {
                    Text("Home Accent Color")
                } footer: {
                    Text("Tints this Home screen's section headers and greeting. Separate from your profile's accent colors and only visible to you.")
                }

                Section {
                    ForEach(order) { kind in
                        HStack(spacing: 12) {
                            Image(systemName: kind.icon)
                                .foregroundStyle(hidden.contains(kind) ? AppTheme.textSecondary : accentColor)
                                .frame(width: 22)
                            Text(kind.title)
                                .foregroundStyle(AppTheme.textPrimary)
                                .opacity(hidden.contains(kind) ? 0.5 : 1)
                            Spacer()
                            Toggle("Show \(kind.title)", isOn: showBinding(for: kind))
                                .labelsHidden()
                                .tint(accentColor)
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Drag to reorder. Toggle a section off to hide it — it still only ever appears when it actually has content.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(accentColor)
                }
            }
        }
        .onAppear {
            order = HomeHubLayoutStore.decodeOrder(orderRaw)
            hidden = HomeHubLayoutStore.decodeHidden(hiddenRaw)
        }
    }

    private func showBinding(for kind: HubSectionKind) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(kind) },
            set: { isOn in
                if isOn { hidden.remove(kind) } else { hidden.insert(kind) }
                hiddenRaw = HomeHubLayoutStore.encodeHidden(hidden)
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        orderRaw = HomeHubLayoutStore.encodeOrder(order)
    }
}
