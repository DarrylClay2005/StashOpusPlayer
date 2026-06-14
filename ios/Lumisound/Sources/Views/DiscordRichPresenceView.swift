import SwiftUI

// MARK: - DiscordRichPresenceView
//
// Sets up the local Discord Rich Presence daemon (discord-rpc/) for this
// account:
//   1. Generate an RPC setup token (POST /user/rpc-token) — the only
//      credential the daemon needs.
//   2. Register a Discord Application client ID + optional Rich Presence
//      art asset name (GET/PUT/DELETE /user/discord-rpc-config) — the
//      daemon fetches this automatically so there's nothing else to
//      configure locally.
//
// Rich Presence itself is still set locally by the daemon over Discord's
// IPC (a Unix socket on Linux/macOS, a named pipe on Windows) — there is no
// server-side API to set it remotely — but with both of these steps done,
// the daemon needs only the token in its config file (`bridge_url` defaults
// to the hosted Lumisound bridge).

struct DiscordRichPresenceView: View {
    @EnvironmentObject private var account: AccountService

    @State private var isGeneratingToken = false
    @State private var generatedToken: String?
    @State private var didCopyToken = false

    @State private var config: DiscordRpcConfig?
    @State private var clientIdText = ""
    @State private var largeImageText = ""
    @State private var enabled = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                if let generatedToken {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generatedToken)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = generatedToken
                            didCopyToken = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                didCopyToken = false
                            }
                        } label: {
                            Label(didCopyToken ? "Copied" : "Copy Token", systemImage: didCopyToken ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        Task {
                            isGeneratingToken = true
                            generatedToken = await account.generateRpcToken()
                            isGeneratingToken = false
                        }
                    } label: {
                        HStack {
                            Label("Generate Rich Presence Token", systemImage: "key.viewfinder")
                                .foregroundStyle(AppTheme.textPrimary)
                            if isGeneratingToken {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isGeneratingToken)
                }
            } header: {
                sectionHeader("Setup Token")
            } footer: {
                Text("Generate a token for the local Discord Rich Presence daemon — it only allows reading your own playback state, not your password, and can be revoked any time from Active Sessions (\"Discord RPC Bridge\"). The daemon must run on a computer with Discord open, since Rich Presence is set over Discord's local connection — it can't be driven remotely. Run \"./install.sh <token>\" (or install-macos.sh / install-windows.ps1) from the discord-rpc folder on GitHub — that's the only thing you need to do locally.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                TextField("Discord Application Client ID", text: $clientIdText)
                    .keyboardType(.numberPad)
                    .foregroundStyle(AppTheme.textPrimary)

                TextField("Rich Presence art asset name (optional)", text: $largeImageText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(AppTheme.textPrimary)

                Toggle("Enabled", isOn: $enabled)
                    .tint(AppTheme.dynamicAccent)
                    .foregroundStyle(AppTheme.textPrimary)

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(didSave ? "Saved" : "Save")
                    }
                }
                .disabled(isSaving || clientIdText.trimmingCharacters(in: .whitespaces).isEmpty)
                .foregroundStyle(AppTheme.dynamicAccent)
            } header: {
                sectionHeader("Daemon Configuration")
            } footer: {
                Text("Saved here, the local Rich Presence daemon fetches this automatically — you don't need to put your Discord Application Client ID in a config file. Find it on your application's page at discord.com/developers/applications.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
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

            if config?.configured == true {
                Section {
                    Button(role: .destructive) {
                        removeConfig()
                    } label: {
                        Text("Remove Registration")
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Discord Rich Presence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        config = await account.fetchDiscordRpcConfig()
        if let config, config.configured {
            clientIdText = config.discordClientId ?? ""
            largeImageText = config.largeImage ?? ""
            enabled = config.enabled
        }
    }

    private func save() {
        let trimmedId = clientIdText.trimmingCharacters(in: .whitespaces)
        guard !trimmedId.isEmpty else { return }
        let trimmedImage = largeImageText.trimmingCharacters(in: .whitespaces)
        isSaving = true
        errorText = nil
        Task {
            if await account.setDiscordRpcConfig(clientId: trimmedId, largeImage: trimmedImage.isEmpty ? nil : trimmedImage, enabled: enabled) {
                didSave = true
                config = await account.fetchDiscordRpcConfig()
            } else {
                errorText = account.errorMessage ?? "Failed to save configuration."
            }
            isSaving = false
        }
    }

    private func removeConfig() {
        Task {
            if await account.deleteDiscordRpcConfig() {
                config = await account.fetchDiscordRpcConfig()
                clientIdText = ""
                largeImageText = ""
                enabled = true
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
