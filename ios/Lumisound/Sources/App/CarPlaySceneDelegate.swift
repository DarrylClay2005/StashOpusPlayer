import CarPlay
import UIKit

// MARK: - CarPlay
//
// IMPORTANT — this needs Apple's separate CarPlay entitlement approval before
// it can run on a real head unit or the CarPlay Simulator. Unlike every other
// feature in this file's sibling services, `com.apple.developer.carplay-audio`
// is a *restricted* entitlement: Apple has to grant it to the paid developer
// account per-app (https://developer.apple.com/contact/carplay/), it cannot be
// self-served from Xcode's Signing & Capabilities like Group Activities or
// widgets can. Given this app ships via sideloading (AltStore/Sideloadly, see
// the root README), it likely can't be signed with this entitlement at all in
// its current distribution model. This file is written so the scene is ready
// to wire in the moment that changes (or for anyone self-hosting/re-signing
// with their own entitlement grant) — see the integration notes wherever
// project.yml/Info.plist/entitlements are documented for the exact scene
// manifest entry this delegate needs.
//
// The actual transport controls (play/pause/skip/scrub) need zero CarPlay-
// specific code: `CPNowPlayingTemplate` reflects the same `MPNowPlayingInfoCenter`/
// `MPRemoteCommandCenter` targets `AudioPlayerManager.configureRemoteCommands()`
// already registers for the Lock Screen/Control Center, so it "just works" once
// the scene connects.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(Self.buildRootTemplate(), animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - Templates

    private static func buildRootTemplate() -> CPTemplate {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        return CPTabBarTemplate(templates: [buildPlaylistsListTemplate(), nowPlaying])
    }

    /// Rebuilt fresh each time it's shown (playlists can change between
    /// connects) rather than cached — CarPlay list templates are cheap to
    /// construct and this avoids a second, separate "refresh" code path.
    private static func buildPlaylistsListTemplate() -> CPListTemplate {
        let playlists = LibraryManager.shared?.playlists ?? []
        let items: [CPListItem] = playlists.map { playlist in
            let item = CPListItem(text: playlist.name, detailText: "\(playlist.songIDs.count) songs")
            item.handler = { _, completion in
                playSongs(from: playlist)
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Playlists", sections: [section])
        template.emptyViewTitleVariants = ["No Playlists Yet"]
        template.emptyViewSubtitleVariants = ["Create a playlist in Lumisound on your phone to see it here."]
        return template
    }

    @MainActor
    private static func playSongs(from playlist: Playlist) {
        guard let library = LibraryManager.shared, let player = AudioPlayerManager.shared else { return }
        let songs = library.songs(for: playlist)
        guard !songs.isEmpty else { return }
        player.setQueue(songs, startIndex: 0, autoplay: true)
    }
}
