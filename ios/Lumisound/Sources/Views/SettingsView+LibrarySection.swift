import SwiftUI

extension SettingsView {

    // MARK: — Library Section

    var librarySection: some View {
        Section {
            // Default scan source picker
            Picker(selection: Binding(
                get: { UserDefaults.standard.string(forKey: "default_scan_source") ?? "apple_music" },
                set: { UserDefaults.standard.set($0, forKey: "default_scan_source") }
            )) {
                Text("iPhone Music Library (Apple Music)").tag("apple_music")
                Text("App Files (Transferred via Mac)").tag("app_storage")
                Text("Both").tag("both")
            } label: {
                Label("Scan on Launch", systemImage: "magnifyingglass.circle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(AppTheme.dynamicAccent)

            // Access status row
            HStack {
                Label("Media Library Access", systemImage: "music.note.house")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(mediaAccessStatusText)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(mediaAccessStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(mediaAccessStatusColor.opacity(0.15), in: Capsule())
            }

            // Grant / Scan button
            if MPMediaLibrary.authorizationStatus() != .authorized {
                Button {
                    library.requestAccessAndScan()
                } label: {
                    Label("Grant Access", systemImage: "checkmark.shield")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            } else {
                Button {
                    library.scanMediaLibrary()
                } label: {
                    HStack {
                        Label("Scan Library", systemImage: "arrow.clockwise")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if library.isScanning {
                            ProgressView()
                                .tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(library.isScanning)
            }

            // Library error message (if any)
            if let error = library.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stats
            LabeledContent("Songs") {
                Text("\(library.allSongs.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Artists") {
                Text("\(library.artists.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Albums") {
                Text("\(library.albums.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Playlists") {
                Text("\(library.playlists.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            // Corrupt file finder
            NavigationLink(destination: CorruptFilesView()) {
                Label("Corrupt File Finder", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Duplicate finder
            NavigationLink(destination: DuplicateFilesView()) {
                Label("Duplicate Finder", systemImage: "doc.on.doc")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Storage & cache manager
            NavigationLink(destination: CacheManagerView().environmentObject(cacheManager)) {
                Label("Storage & Cache", systemImage: "internaldrive")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Local playlist/favorites backup — no server/account involved
            NavigationLink(destination: LibraryBackupView()) {
                Label("Backup & Restore", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // On-device listening stats — no server/account involved
            NavigationLink(destination: ListeningStatsView()) {
                Label("Listening Stats", systemImage: "chart.bar.fill")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Wake-up alarm that fades in music — no server/account involved
            NavigationLink(destination: SleepWakeAlarmView()) {
                Label("Wake-Up Alarm", systemImage: "alarm")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Force metadata sync
            Button {
                Task {
                    await library.forceMetadataSync(using: folderService)
                    // forceMetadataSync runs silently otherwise — without this the
                    // button just shows a brief spinner and nothing else, which is
                    // indistinguishable from doing nothing at all even though it
                    // really did rescan, re-tag, and re-enrich every track.
                    if let result = library.lastScanResult {
                        ToastCenter.shared.show(result, category: .success, icon: "checkmark.circle")
                    }
                }
            } label: {
                HStack {
                    Label("Force Metadata Sync", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if library.isForcingMetadataSync {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(library.isForcingMetadataSync)

        } header: {
            sectionHeader("Library")
        } footer: {
            Text("Re-scans your entire Documents folder — including \"Imported Music\" and any subfolders — plus any watched folders, then re-reads embedded tags and re-runs online metadata lookups for every imported track. Use this if tags look stale or after manually adding files outside the app.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }
}
