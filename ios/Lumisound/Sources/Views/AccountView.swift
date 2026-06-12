import SwiftUI
import PhotosUI

struct AccountView: View {

    @EnvironmentObject var account: AccountService
    @EnvironmentObject var library: LibraryManager
    @Environment(\.dismiss) var dismiss

    @State private var showLogoutConfirm = false
    @State private var isEditingDisplayName = false
    @State private var draftDisplayName = ""
    @State private var isSavingDisplayName = false

    // Avatar
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingAvatar = false

    // DOB
    @State private var isPickingDOB = false

    // User ID copy feedback
    @State private var didCopyUserID = false
    @State private var draftDOB = Date()
    @State private var isSavingDOB = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            List {
                // MARK: Header — avatar + username
                Section {
                    HStack(spacing: 16) {
                        // Avatar circle: photo if available, else gradient + initials
                        ZStack {
                            if let img = account.avatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
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
                            }
                            if isUploadingAvatar {
                                Circle()
                                    .fill(.black.opacity(0.45))
                                    .frame(width: 64, height: 64)
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 8, x: 0, y: 4)

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

                    // Upload photo button
                    PhotosPicker(
                        selection: $photosPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            account.avatarImage == nil ? "Upload Profile Photo" : "Change Profile Photo",
                            systemImage: "camera.circle"
                        )
                        .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    .onChange(of: photosPickerItem) { item in
                        guard let item else { return }
                        isUploadingAvatar = true
                        Task {
                            defer { isUploadingAvatar = false }
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                await account.uploadAvatar(image: image)
                            }
                            photosPickerItem = nil
                        }
                    }
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

                    // Auto-sync cadence info
                    HStack {
                        Label("Auto-sync", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("every 8 min")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    // Push to server
                    Button {
                        Task { await account.pushSync(library: library) }
                    } label: {
                        HStack {
                            Label("Push to Server", systemImage: "icloud.and.arrow.up")
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Spacer()
                            if account.isSyncing {
                                ProgressView()
                                    .tint(AppTheme.dynamicAccent)
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
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Spacer()
                            if account.isSyncing {
                                ProgressView()
                                    .tint(AppTheme.dynamicAccent)
                            }
                        }
                    }
                    .disabled(account.isSyncing)

                    // Backup history — automatic snapshots taken before every
                    // push/restore, in case a bad sync overwrites server data.
                    NavigationLink(destination: BackupHistoryView()) {
                        Label("Backup History", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(AppTheme.textPrimary)
                    }

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

                // MARK: Stats Section
                Section {
                    LabeledContent("Playlists") {
                        Text("\(library.playlists.count)")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    LabeledContent("Favorites") {
                        Text("\(library.favoriteSongIDs.count)")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    if let stats = account.stats {
                        LabeledContent("Total Plays") {
                            Text("\(stats.totalPlays)")
                                .font(AppTheme.monoFont(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .foregroundStyle(AppTheme.textPrimary)

                        LabeledContent("Listening Time") {
                            Text(formattedListenTime(stats.totalListenSeconds))
                                .font(AppTheme.monoFont(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .foregroundStyle(AppTheme.textPrimary)

                        if let topArtist = stats.topArtists.first {
                            LabeledContent("Top Artist") {
                                Text(topArtist.artist)
                                    .font(AppTheme.bodyFont(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                } header: {
                    sectionHeader("Library")
                }
                .listRowBackground(AppTheme.surface)
                .task {
                    await account.fetchStats()
                }

                // MARK: Account Info Section
                Section {
                    LabeledContent("Username") {
                        Text(account.currentUser?.username ?? "")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    // Permanent account identifier — assigned once at signup and
                    // never changes, even if username/email/display name do.
                    // Useful to include when reporting a bug or contacting support.
                    if let userID = account.currentUser?.id {
                        Button {
                            UIPasteboard.general.string = userID
                            withAnimation { didCopyUserID = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                withAnimation { didCopyUserID = false }
                            }
                        } label: {
                            LabeledContent("User ID") {
                                HStack(spacing: 6) {
                                    Text(userID)
                                        .font(AppTheme.monoFont(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Image(systemName: didCopyUserID ? "checkmark" : "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundStyle(didCopyUserID ? AppTheme.success : AppTheme.dynamicAccent)
                                }
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                            .foregroundStyle(AppTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let email = account.currentUser?.email, !email.isEmpty {
                        LabeledContent("Email") {
                            Text(email)
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .foregroundStyle(AppTheme.textPrimary)
                    }

                    // Date of birth — show once set; show picker if not yet set
                    if account.hasDateOfBirth {
                        LabeledContent("Date of Birth") {
                            Text(account.currentUser?.dateOfBirth ?? "Set")
                                .font(AppTheme.monoFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .foregroundStyle(AppTheme.textPrimary)
                    } else if isPickingDOB {
                        VStack(alignment: .leading, spacing: 6) {
                            DatePicker(
                                "Date of Birth",
                                selection: $draftDOB,
                                in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .foregroundStyle(AppTheme.textPrimary)
                            HStack {
                                if isSavingDOB {
                                    ProgressView().tint(AppTheme.dynamicAccent)
                                } else {
                                    Button("Save") { saveDOB() }
                                        .foregroundStyle(AppTheme.dynamicAccent)
                                        .font(.subheadline.bold())
                                    Button("Cancel") { isPickingDOB = false }
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .font(.subheadline)
                                        .padding(.leading, 8)
                                }
                            }
                        }
                    } else {
                        Button {
                            isPickingDOB = true
                        } label: {
                            HStack {
                                Text("Date of Birth")
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text("Not set")
                                    .font(AppTheme.bodyFont(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                    .padding(.leading, 4)
                            }
                        }
                    }

                    // Display name — tappable to edit inline
                    if isEditingDisplayName {
                        HStack {
                            TextField("Display name", text: $draftDisplayName)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .foregroundStyle(AppTheme.textPrimary)
                                .submitLabel(.done)
                                .onSubmit { saveDisplayName() }
                            if isSavingDisplayName {
                                ProgressView()
                                    .tint(AppTheme.dynamicAccent)
                                    .padding(.leading, 6)
                            } else {
                                Button("Save") { saveDisplayName() }
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                    .font(.subheadline.bold())
                                Button("Cancel") {
                                    isEditingDisplayName = false
                                    draftDisplayName = ""
                                }
                                .foregroundStyle(AppTheme.textSecondary)
                                .font(.subheadline)
                                .padding(.leading, 4)
                            }
                        }
                    } else {
                        Button {
                            draftDisplayName = account.currentUser?.displayName ?? ""
                            isEditingDisplayName = true
                        } label: {
                            HStack {
                                Text("Display Name")
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text(
                                    account.currentUser?.displayName.flatMap {
                                        $0.isEmpty ? nil : $0
                                    } ?? "Not set"
                                )
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                    .padding(.leading, 4)
                            }
                        }
                    }

                } header: {
                    sectionHeader("Account")
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Social / Discovery Section
                Section {
                    NavigationLink(destination: DiscoverView()) {
                        Label("Discover", systemImage: "sparkles")
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Toggle(isOn: Binding(
                        get: { account.currentUser?.shareListeningActivity ?? false },
                        set: { newValue in Task { await account.setShareListeningActivity(newValue) } }
                    )) {
                        Label("Share Listening Activity", systemImage: "person.wave.2")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .tint(AppTheme.dynamicAccent)
                } header: {
                    sectionHeader("Discovery")
                } footer: {
                    Text("When on, the song titles and artists you play (not files or links) appear in Discover's activity feed and count toward Trending for other signed-in users.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Security Section
                Section {
                    NavigationLink(destination: ActiveSessionsView()) {
                        Label("Active Sessions", systemImage: "laptopcomputer.and.iphone")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    NavigationLink(destination: ChangePasswordView()) {
                        Label("Change Password", systemImage: "key")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                } header: {
                    sectionHeader("Security")
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

                    NavigationLink(destination: DeleteAccountView()) {
                        HStack {
                            Spacer()
                            Label("Delete Account", systemImage: "trash")
                                .foregroundStyle(AppTheme.error)
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
        .onChange(of: account.isLoggedIn) { loggedIn in
            if loggedIn {
                Task { await account.pullSync(library: library) }
            } else {
                dismiss()
            }
        }
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

    private func formattedListenTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private func saveDOB() {
        guard !isSavingDOB else { return }
        isSavingDOB = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let iso = formatter.string(from: draftDOB)
        Task {
            defer {
                isSavingDOB = false
                isPickingDOB = false
            }
            await account.setDateOfBirth(iso)
        }
    }

    private func saveDisplayName() {
        let trimmed = draftDisplayName.trimmingCharacters(in: .whitespaces)
        guard !isSavingDisplayName else { return }
        isSavingDisplayName = true
        Task {
            defer {
                isSavingDisplayName = false
                isEditingDisplayName = false
                draftDisplayName = ""
            }
            await account.updateDisplayName(trimmed)
        }
    }
}
