import SwiftUI

// MARK: - YoutubeApiKeyView
//
// Configures this account's personal YouTube Data API v3 key
// (GET/PUT/DELETE /user/youtube-api-key). When set, the bridge's
// /api/resolve uses playlistItems.list to enumerate full YouTube playlists
// for this account — bypassing yt-dlp's ~205-entry flat-playlist cap. Falls
// back to the server-wide key (if any) when unset.

struct YoutubeApiKeyView: View {
    @EnvironmentObject private var account: AccountService

    @State private var status: YoutubeApiKeyConfig?
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                if status?.configured == true {
                    LabeledContent("API Key") {
                        Text(status?.apiKey ?? "")
                            .font(AppTheme.monoFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                } else {
                    TextField("AIza...", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            } header: {
                sectionHeader("YouTube Data API Key")
            } footer: {
                Text("Lets full YouTube playlists (beyond ~205 tracks) resolve completely when you import or play them. Create a free key in the Google Cloud Console by enabling \"YouTube Data API v3\" and generating an API key under Credentials.")
            }
            .listRowBackground(AppTheme.surface)

            if status?.configured != true {
                Section {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(didSave ? "Saved" : "Save")
                        }
                    }
                    .disabled(isSaving || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
                .listRowBackground(AppTheme.surface)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                }
                .listRowBackground(Color.clear)
            }

            if status?.configured == true {
                Section {
                    Button(role: .destructive) {
                        removeKey()
                    } label: {
                        Text("Remove API Key")
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("YouTube API Key")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        status = await account.fetchYoutubeApiKey()
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorText = nil
        Task {
            if await account.setYoutubeApiKey(trimmed) {
                didSave = true
                apiKey = ""
                status = await account.fetchYoutubeApiKey()
            } else {
                errorText = account.errorMessage ?? "Failed to save API key."
            }
            isSaving = false
        }
    }

    private func removeKey() {
        Task {
            if await account.deleteYoutubeApiKey() {
                status = await account.fetchYoutubeApiKey()
                apiKey = ""
                didSave = false
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
