import SwiftUI

// MARK: - DeleteAccountView
//
// Permanently deletes the user's account (POST /auth/delete-account),
// including their server-side library data, backups, and any uploaded
// music/gallery files. Requires password confirmation.

struct DeleteAccountView: View {
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var localError: String?
    @State private var showConfirm = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.error)
                    Text("This will permanently delete your Lumisound account, including your saved favorites, playlists, listening history, sync backups, and any music or images you've uploaded to the server. This cannot be undone.")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Confirm Your Password")
            }
            .listRowBackground(AppTheme.surface)

            if let localError {
                Section {
                    Text(localError)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.error)
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(AppTheme.error)
                        } else {
                            Text("Delete Account")
                                .font(AppTheme.bodyFont(size: 15).weight(.semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(AppTheme.error)
                }
                .disabled(password.isEmpty || isSubmitting)
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your account permanently?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                submit()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All of your data on the server will be erased. This cannot be undone.")
        }
    }

    private func submit() {
        localError = nil
        isSubmitting = true
        Task {
            let success = await account.deleteAccount(password: password)
            isSubmitting = false
            if success {
                dismiss()
            } else {
                localError = account.errorMessage ?? "Could not delete account. Please try again."
            }
        }
    }
}
