import SwiftUI

// MARK: - ScrobblingView
//
// Lets the user link Last.fm and/or ListenBrainz so plays are scrobbled
// automatically (GET/PUT/DELETE /user/scrobble). Last.fm uses the standard
// "desktop application" auth flow: request a token, open Last.fm in Safari
// for the user to approve it, then exchange the token for a session key.

struct ScrobblingView: View {
    @EnvironmentObject private var account: AccountService

    @State private var links: ScrobbleLinks?
    @State private var isLoading = false

    @State private var listenbrainzToken = ""
    @State private var isLinkingListenBrainz = false

    @State private var pendingLastfmToken: String?
    @State private var lastfmAuthURL: URL?
    @State private var isLastfmBusy = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                Toggle("Scrobble Plays", isOn: Binding(
                    get: { links?.enabled ?? true },
                    set: { newValue in
                        Task {
                            if await account.setScrobblingEnabled(newValue) {
                                links = await account.fetchScrobbleLinks()
                            }
                        }
                    }
                ))
                .tint(AppTheme.dynamicAccent)
                .foregroundStyle(AppTheme.textPrimary)
                .disabled(links == nil || (!(links?.lastfmLinked ?? false) && !(links?.listenbrainzLinked ?? false)))
            } header: {
                sectionHeader("Scrobbling")
            } footer: {
                Text("When enabled, finished tracks are sent to any linked services below.")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                if links?.lastfmLinked == true {
                    LabeledContent("Last.fm") {
                        Text(links?.lastfmUsername ?? "Linked")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                } else if let lastfmAuthURL {
                    Link(destination: lastfmAuthURL) {
                        Label("Open Last.fm to Authorize", systemImage: "safari")
                    }
                    .foregroundStyle(AppTheme.dynamicAccent)

                    Button {
                        finishLastfmLink()
                    } label: {
                        if isLastfmBusy {
                            ProgressView()
                        } else {
                            Text("I've Authorized — Finish Linking")
                        }
                    }
                    .disabled(isLastfmBusy)
                    .foregroundStyle(AppTheme.dynamicAccent)
                } else {
                    Button {
                        startLastfmLink()
                    } label: {
                        if isLastfmBusy {
                            ProgressView()
                        } else {
                            Label("Connect Last.fm", systemImage: "link")
                        }
                    }
                    .disabled(isLastfmBusy)
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
            } header: {
                sectionHeader("Last.fm")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                if links?.listenbrainzLinked == true {
                    HStack {
                        Label("ListenBrainz", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Spacer()
                        Text("Linked")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } else {
                    TextField("User Token", text: $listenbrainzToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(AppTheme.textPrimary)

                    Button {
                        linkListenBrainz()
                    } label: {
                        if isLinkingListenBrainz {
                            ProgressView()
                        } else {
                            Text("Link ListenBrainz")
                        }
                    }
                    .disabled(isLinkingListenBrainz || listenbrainzToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
            } header: {
                sectionHeader("ListenBrainz")
            } footer: {
                Text("Find your user token at listenbrainz.org under Profile \u{2192} Settings.")
            }
            .listRowBackground(AppTheme.surface)

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                }
                .listRowBackground(Color.clear)
            }

            if (links?.lastfmLinked ?? false) || (links?.listenbrainzLinked ?? false) {
                Section {
                    Button(role: .destructive) {
                        unlink()
                    } label: {
                        Text("Unlink All Scrobbling Accounts")
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Scrobbling")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        links = await account.fetchScrobbleLinks()
        isLoading = false
    }

    private func startLastfmLink() {
        isLastfmBusy = true
        errorText = nil
        Task {
            if let result = await account.lastfmRequestToken(), let url = URL(string: result.authUrl) {
                pendingLastfmToken = result.token
                lastfmAuthURL = url
            } else {
                errorText = account.errorMessage ?? "Failed to start Last.fm linking."
            }
            isLastfmBusy = false
        }
    }

    private func finishLastfmLink() {
        guard let token = pendingLastfmToken else { return }
        isLastfmBusy = true
        errorText = nil
        Task {
            if let username = await account.lastfmLinkSession(token: token) {
                _ = username
                pendingLastfmToken = nil
                lastfmAuthURL = nil
                links = await account.fetchScrobbleLinks()
            } else {
                errorText = account.errorMessage ?? "Last.fm hasn't approved this link yet. Authorize it in Safari, then try again."
            }
            isLastfmBusy = false
        }
    }

    private func linkListenBrainz() {
        let trimmed = listenbrainzToken.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLinkingListenBrainz = true
        errorText = nil
        Task {
            if await account.linkListenBrainz(token: trimmed) {
                listenbrainzToken = ""
                links = await account.fetchScrobbleLinks()
            } else {
                errorText = account.errorMessage ?? "Failed to link ListenBrainz."
            }
            isLinkingListenBrainz = false
        }
    }

    private func unlink() {
        Task {
            if await account.unlinkScrobbling() {
                links = await account.fetchScrobbleLinks()
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
