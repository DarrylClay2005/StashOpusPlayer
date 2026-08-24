import SwiftUI

// MARK: - TVTrackActions
//
// Shared long-press context menu (favorite toggle + add to playlist) for a
// Personal Cloud Library track, applied to cards/rows in the Songs grid,
// Album/Artist/Genre detail lists, and the Favorites grid. Siri Remote
// click-and-hold on a focused `.card`-style button surfaces `.contextMenu`
// the same way as on iOS's long-press.

private struct TVTrackContextMenu: ViewModifier {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let track: UserMusicTrack
    @State private var showAddToPlaylist = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Task { await client.toggleFavorite(track: track, token: token) }
                } label: {
                    if client.isFavorite(track.id) {
                        Label("Remove from Favorites", systemImage: "star.slash")
                    } else {
                        Label("Add to Favorites", systemImage: "star")
                    }
                }
                Button {
                    showAddToPlaylist = true
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                if let body = client.syncTrackBody(from: track) {
                    TVAddToPlaylistSheet(client: client, token: token, track: body)
                }
            }
    }
}

/// Same menu, minus the favorite toggle — for search results, which don't
/// have a stable enough id to favorite (see `TVFavorite`).
private struct TVSearchTrackContextMenu: ViewModifier {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let track: TVTrack
    @State private var showAddToPlaylist = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    showAddToPlaylist = true
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                if let body = client.syncTrackBody(from: track) {
                    TVAddToPlaylistSheet(client: client, token: token, track: body)
                }
            }
    }
}

extension View {
    func tvTrackActions(client: TVBridgeClient, token: String, track: UserMusicTrack) -> some View {
        modifier(TVTrackContextMenu(client: client, token: token, track: track))
    }

    func tvSearchTrackActions(client: TVBridgeClient, token: String, track: TVTrack) -> some View {
        modifier(TVSearchTrackContextMenu(client: client, token: token, track: track))
    }
}
