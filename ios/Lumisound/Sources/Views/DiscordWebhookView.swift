import SwiftUI

// MARK: - DiscordWebhookView
//
// Configures a Discord webhook the server posts "Now Playing" updates to
// (GET/PUT/DELETE /user/discord-webhook). Distinct from the local Discord
// Rich Presence daemon (RPC setup token, in Settings) — this posts messages
// to a Discord channel via an incoming webhook.

struct DiscordWebhookView: View {
    @EnvironmentObject private var account: AccountService

    @State private var status: DiscordWebhookStatus?
    @State private var webhookURL = ""
    @State private var enabled = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                if status?.configured == true {
                    LabeledContent("Webhook") {
                        Text(status?.webhookUrl ?? "")
                            .font(AppTheme.monoFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    Toggle("Enabled", isOn: $enabled)
                        .tint(AppTheme.dynamicAccent)
                        .foregroundStyle(AppTheme.textPrimary)
                        .onChange(of: enabled) { newValue in
                            Task {
                                _ = await account.setDiscordWebhook(url: nil, enabled: newValue)
                            }
                        }
                } else {
                    TextField("https://discord.com/api/webhooks/...", text: $webhookURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            } header: {
                sectionHeader("Discord Webhook")
            } footer: {
                Text("Posts a \"Now Playing\" message to a Discord channel whenever you start a track. Create an incoming webhook in your server's Channel Settings \u{2192} Integrations \u{2192} Webhooks.")
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
                    .disabled(isSaving || webhookURL.trimmingCharacters(in: .whitespaces).isEmpty)
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
                        removeWebhook()
                    } label: {
                        Text("Remove Webhook")
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Discord Webhook")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        status = await account.fetchDiscordWebhook()
        enabled = status?.enabled ?? true
    }

    private func save() {
        let trimmed = webhookURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorText = nil
        Task {
            if await account.setDiscordWebhook(url: trimmed, enabled: enabled) {
                didSave = true
                status = await account.fetchDiscordWebhook()
            } else {
                errorText = account.errorMessage ?? "Failed to save webhook."
            }
            isSaving = false
        }
    }

    private func removeWebhook() {
        Task {
            if await account.deleteDiscordWebhook() {
                status = await account.fetchDiscordWebhook()
                webhookURL = ""
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
