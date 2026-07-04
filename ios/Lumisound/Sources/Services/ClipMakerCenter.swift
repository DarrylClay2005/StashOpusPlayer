import Foundation

/// App-wide state for the "Make a Clip" flow — mirrors `AcoustIDConfirmCenter`'s
/// shape (a singleton `ObservableObject` observed by a single sheet mounted
/// once near the root) since a context menu's content view is too transient
/// to host a sheet presentation itself.
@MainActor
final class ClipMakerCenter: ObservableObject {
    static let shared = ClipMakerCenter()

    @Published var pendingSong: Song?

    private init() {}

    func present(song: Song) {
        pendingSong = song
    }
}
