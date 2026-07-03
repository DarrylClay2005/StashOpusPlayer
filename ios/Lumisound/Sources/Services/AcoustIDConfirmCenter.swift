import Foundation

/// App-wide state for the "Identify Track" flow — mirrors `ToastCenter`'s
/// shape (a singleton `ObservableObject` observed by a single overlay/sheet
/// mounted once near the root) since a context menu's content view is too
/// transient to host a multi-step async confirmation itself.
@MainActor
final class AcoustIDConfirmCenter: ObservableObject {
    static let shared = AcoustIDConfirmCenter()

    struct Pending: Identifiable {
        let id = UUID()
        let songID: String
        let currentTitle: String
        let currentArtist: String
        let match: AcoustIDService.Match
    }

    /// Non-nil while the confirmation sheet should be showing.
    @Published var pending: Pending?
    /// True while a fingerprint upload/lookup is in flight — used to disable
    /// re-tapping "Identify Track" on the same song mid-request.
    @Published private(set) var isIdentifying = false

    private init() {}

    func identify(song: Song) {
        guard !isIdentifying else { return }
        isIdentifying = true
        ToastCenter.shared.show("Identifying \"\(song.displayName)\"…", category: .info, icon: "waveform.badge.magnifyingglass")
        Task {
            defer { isIdentifying = false }
            do {
                let match = try await AcoustIDService.shared.identify(song: song)
                pending = Pending(songID: song.id, currentTitle: song.title, currentArtist: song.artist, match: match)
            } catch {
                ToastCenter.shared.show(error.localizedDescription, category: .error, icon: "xmark.circle")
            }
        }
    }
}
