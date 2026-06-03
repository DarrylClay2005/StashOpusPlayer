import SwiftUI

struct AccountView: View {

    @EnvironmentObject var account: AccountService
    @EnvironmentObject var library: LibraryManager
    @Environment(\.dismiss) var dismiss

    @State private var showLogoutConfirm = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            List {
                // MARK: Header — avatar + username
                Section {
                    HStack(spacing: 16) {
                        // Avatar circle with initials
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentSoft],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(initials)
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            )
                            .shadow(color: AppTheme.accent.opacity(0.4), radius: 8, x: 0, y: 4)

                        VStack(alignment: .leading, spacing: 4) {
                            if let displayName = account.currentUser?.displayName,
                               !displayName.isEmpty {
                                Text(displayName)
                                    .font(.title3.bold())
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("@\(account.currentUser?.username ?? "")")
                                    .font(AppTheme.bodyFont(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                Text(account.currentUser?.username ?? "")
                                    .font(.title3.bold())
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            if let email = account.currentUser?.email, !email.isEmpty {
                                Text(email)
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Sync Section
                Section {
                    // Last synced info
                    if let lastSync = account.lastSyncDate {
                        HStack {
                            Label("Last Synced", systemImage: "clock")
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Text(lastSync, style: .relative)
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    // Push to server
                    Button {
                        Task { await account.pushSync(library: library) }
                    } label: {
                        HStack {
                            Label("Push to Server", systemImage: "icloud.and.arrow.up")
                                .foregroundStyle(AppTheme.accent)
                            Spacer()
                            if account.isSyncing {
                                ProgressView()
                                    .tint(AppTheme.accent)
                            }
                        }
                    }
                    .disabled(account.isSyncing)

                    // Pull from server
                    Button {
                        Task { await account.pullSync(library: library) }
                    } label: {
                        HStack {
                            Label("Pull from Server", systemImage: "icloud.and.arrow.down")
                                .foregroundStyle(AppTheme.accent)
                            Spacer()
                            if account.isSyncing {
                                ProgressView()
                                    .tint(AppTheme.accent)
                            }
                        }
                    }
                    .disabled(account.isSyncing)

                    // Error message
                    if let err = account.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                } header: {
                    sectionHeader("Sync")
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Account Info Section
                Section {
                    LabeledContent("Username") {
                        Text(account.currentUser?.username ?? "")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    if let email = account.currentUser?.email, !email.isEmpty {
                        LabeledContent("Email") {
                            Text(email)
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .foregroundStyle(AppTheme.textPrimary)
                    }

                } header: {
                    sectionHeader("Account")
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Danger Section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                } header: {
                    sectionHeader("Session")
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Log Out", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task {
                    await account.logout()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out on this device. Your data stays on the server.")
        }
    }

    // MARK: - Helpers

    private var initials: String {
        guard let user = account.currentUser else { return "?" }
        let name = user.displayName ?? user.username
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
