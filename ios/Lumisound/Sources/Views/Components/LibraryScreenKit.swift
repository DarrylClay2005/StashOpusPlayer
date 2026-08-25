import SwiftUI
import UIKit

// MARK: - LibraryScreenKit
//
// Shared structural/visual pieces for the Songs, Queue, Folders, and Folder
// Detail screens' big redesign pass — deliberately NOT touching `SongRow`/
// `SongGridCell` themselves (used across 15+ other screens and driven by the
// user's own `library_cardStyle` preference plus the Lua custom-style engine
// — silently overriding that on just these four screens would be a real
// regression for anyone who's picked a non-default row style). Everything
// here is the surrounding screen chrome instead: hero backdrops, an A-Z jump
// rail, and a breadcrumb — the pieces that make a screen's *shell* feel
// distinct without reaching into how an individual row renders.

// MARK: - HeroArtworkBackdrop

/// A big, blurred, edge-to-edge artwork backdrop for a screen header —
/// Queue's Now Playing hero and Folder Detail's header both sit on one of
/// these. Loads its own image asynchronously (mirrors `ArtworkThumbnail`'s
/// task-based pattern) so callers just hand it a `Song?` and don't need to
/// manage any loading state themselves.
struct HeroArtworkBackdrop: View {
    let song: Song?
    var height: CGFloat = 260

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .clipped()
                    .blur(radius: 50)
                    .overlay(Color.black.opacity(0.5))
            } else {
                LinearGradient(
                    colors: [AppTheme.dynamicAccent.opacity(0.45), AppTheme.dynamicAccentSecondary.opacity(0.25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            // Fades the backdrop into the screen's real background at the
            // bottom edge so content below reads as continuous, not a hard-
            // edged banner.
            LinearGradient(
                colors: [.clear, AppTheme.background],
                startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom
            )
        }
        .frame(height: height)
        .clipped()
        .task(id: song?.id) {
            guard let song else { image = nil; return }
            if let cached = ArtworkService.shared.artwork(for: song) {
                image = cached
                return
            }
            image = nil
            image = await ArtworkService.shared.loadArtwork(for: song)
        }
    }
}

// MARK: - AlphabetIndexRail

/// A right-edge A-Z jump rail — press-and-drag (or tap) any letter to scroll
/// straight to that section, the same interaction as Contacts/Mail's index.
/// Purely a UI affordance: callers own the actual scroll-to-section behavior
/// via `onSelect`, since that depends on each screen's own `ScrollViewReader`/
/// section-anchor setup.
struct AlphabetIndexRail: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { geo in
            let rowHeight = geo.size.height / CGFloat(max(letters.count, 1))
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(activeLetter == letter ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let index = min(letters.count - 1, max(0, Int(value.location.y / max(rowHeight, 1))))
                        let letter = letters[index]
                        if letter != activeLetter {
                            activeLetter = letter
                            UISelectionFeedbackGenerator().selectionChanged()
                            onSelect(letter)
                        }
                    }
                    .onEnded { _ in activeLetter = nil }
            )
        }
        .frame(width: 18)
    }
}

/// Groups an already-sorted list of songs into (letter, songs) buckets keyed
/// by the first character of whichever field they're sorted by — shared by
/// `SongsTab`'s list-mode sections and its index rail so both are always
/// built from the exact same grouping.
func alphabeticalSections(of songs: [Song], key: (Song) -> String) -> [(letter: String, songs: [Song])] {
    var order: [String] = []
    var buckets: [String: [Song]] = [:]
    for song in songs {
        let raw = key(song).trimmingCharacters(in: .whitespacesAndNewlines)
        let first = raw.first.map { String($0).uppercased() } ?? "#"
        let letter = first.rangeOfCharacter(from: .letters) != nil ? first : "#"
        if buckets[letter] == nil {
            buckets[letter] = []
            order.append(letter)
        }
        buckets[letter]?.append(song)
    }
    return order.map { (letter: $0, songs: buckets[$0] ?? []) }
}

// MARK: - BreadcrumbTrail

/// A short, static "parent / here" trail — this app's local-folder grouping
/// is exactly two levels deep (an "Imported Music" subfolder, then its
/// tracks; see `MusicFolderService.localFolderGroups` and
/// `LocalFolderDetailView`'s header comment), so this is intentionally not a
/// generic N-level breadcrumb component — it would be presenting navigation
/// depth the data doesn't actually have.
struct BreadcrumbTrail: View {
    let parent: String
    let current: String

    var body: some View {
        HStack(spacing: 6) {
            Text(parent)
                .foregroundStyle(AppTheme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            Text(current)
                .foregroundStyle(AppTheme.textPrimary)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .lineLimit(1)
    }
}

// MARK: - ScreenStatChip

/// A small glass stat pill — "247 songs", "18h 32m" — used in the redesigned
/// headers in place of a single plain caption line, so key numbers read as
/// distinct at-a-glance facts instead of one run-on sentence.
struct ScreenStatChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .adaptiveGlass(in: Capsule(), fallback: AppTheme.surface.opacity(0.7))
    }
}
