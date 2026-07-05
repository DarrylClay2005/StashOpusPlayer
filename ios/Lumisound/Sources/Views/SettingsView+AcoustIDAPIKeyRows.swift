import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — AcoustID API Key Rows

    var acoustIDKeyDisplay: String {
        guard let config = acoustIDKeyConfig, config.configured, let masked = config.apiKey else {
            return "Not set"
        }
        return masked
    }

    @ViewBuilder
    var acoustIDAPIKeySection: some View {
        HStack {
            Label("AcoustID API Key", systemImage: "waveform.badge.magnifyingglass")
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text(acoustIDKeyDisplay)
                .font(AppTheme.monoFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }

        if acoustIDKeyConfig?.configured != true {
            HStack {
                Label("Set Key", systemImage: "pencil")
                    .foregroundStyle(AppTheme.textPrimary)
                SecureField("Paste AcoustID API key", text: $acoustIDKeyInput)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !acoustIDKeyInput.isEmpty {
                Button {
                    Task {
                        isSavingAcoustIDKey = true
                        let ok = await account.setAcoustIDApiKey(acoustIDKeyInput)
                        isSavingAcoustIDKey = false
                        if ok {
                            acoustIDKeyInput = ""
                            ToastCenter.shared.show("AcoustID API key saved", category: .success, icon: "waveform.badge.magnifyingglass")
                            await refreshAcoustIDKeyStatus()
                        } else {
                            ToastCenter.shared.show("Couldn't save key — check connection", category: .error, icon: "exclamationmark.triangle")
                        }
                    }
                } label: {
                    HStack {
                        Label("Save Key", systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if isSavingAcoustIDKey {
                            ProgressView().tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(isSavingAcoustIDKey)
            }
        }

        if acoustIDKeyConfig?.configured == true {
            Button(role: .destructive) {
                Task {
                    let ok = await account.deleteAcoustIDApiKey()
                    if ok {
                        ToastCenter.shared.show("AcoustID API key removed", category: .info, icon: "waveform.badge.magnifyingglass")
                        await refreshAcoustIDKeyStatus()
                    } else {
                        ToastCenter.shared.show("Couldn't remove key — check connection", category: .error, icon: "exclamationmark.triangle")
                    }
                }
            } label: {
                Label("Remove Key", systemImage: "trash")
                    .foregroundStyle(AppTheme.error)
            }
        }

        Text("Enables \"Identify Track\" (song menu → Identify Track), which fingerprints a track's audio and looks it up against the AcoustID/MusicBrainz database — fixes wrong title/artist tags that a text search can't find. Free key at acoustid.org. No shared fallback key; each user brings their own.")
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.leading, 16)
    }
}
