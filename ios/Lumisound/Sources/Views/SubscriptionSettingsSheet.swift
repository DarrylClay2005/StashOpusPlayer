import SwiftUI

// MARK: - SubscriptionSettingsSheet
//
// Per-subscription settings — auto-download (+ destination folder),
// notification mute, and category — presented from a gear button on each
// row in `SubscriptionsView`. Mirrors `TrackedPlaylistDetailView`'s own
// auto-download/destination-folder controls (same `DownloadFolderPicker`
// component) for consistency between the two "follow something and get new
// tracks automatically" features.

struct SubscriptionSettingsSheet: View {
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss

    let subscription: ArtistSubscription
    /// Called after a successful save so the presenting view can refresh its list.
    var onSaved: () -> Void

    @State private var autoDownload: Bool
    @State private var destinationFolder: String
    @State private var notificationsMuted: Bool
    @State private var category: String
    @State private var isSaving = false
    @State private var errorText: String?

    init(subscription: ArtistSubscription, onSaved: @escaping () -> Void) {
        self.subscription = subscription
        self.onSaved = onSaved
        _autoDownload = State(initialValue: subscription.autoDownload)
        _destinationFolder = State(initialValue: subscription.destinationFolder ?? "")
        _notificationsMuted = State(initialValue: subscription.notificationsMuted)
        _category = State(initialValue: subscription.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-download new uploads", isOn: $autoDownload)
                        .tint(AppTheme.dynamicAccent)
                    if autoDownload {
                        HStack {
                            Text("Save to")
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            DownloadFolderPicker(folderName: $destinationFolder)
                        }
                    }
                } footer: {
                    Text("New uploads from this channel download straight into your library automatically — same as a tracked playlist with auto-download on. \"Save to\" overrides the global Download Folder setting just for this channel.")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Toggle("Mute new-upload alerts", isOn: $notificationsMuted)
                        .tint(AppTheme.dynamicAccent)
                } footer: {
                    Text("Stops notifications for this channel without unsubscribing. New uploads still appear in the New Releases feed and still count toward the upload-frequency insight.")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    TextField("Category (optional)", text: $category)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                } header: {
                    Text("CATEGORY")
                } footer: {
                    Text("Group followed channels — e.g. \"Podcasts\" or \"DJs\" — to filter the list. Leave blank for none.")
                }
                .listRowBackground(AppTheme.surface)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle(subscription.channelName ?? "Channel Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorText = nil
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        let trimmedFolder = destinationFolder.trimmingCharacters(in: .whitespaces)
        Task {
            let ok = await account.updateSubscriptionSettings(
                id: subscription.id,
                autoDownload: autoDownload,
                destinationFolder: trimmedFolder,
                notificationsMuted: notificationsMuted,
                category: trimmedCategory
            )
            isSaving = false
            if ok {
                onSaved()
                dismiss()
            } else {
                errorText = account.errorMessage ?? "Failed to save settings."
            }
        }
    }
}
