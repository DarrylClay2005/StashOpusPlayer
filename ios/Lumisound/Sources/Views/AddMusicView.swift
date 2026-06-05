import SwiftUI
import MediaPlayer

struct AddMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager

    @State private var showFilePicker = false
    @State private var importSuccess: String? = nil

    var body: some View {
        NavigationStack {
            List {

                // ─────────────────────────────────────────────────────────────
                // MARK: Primary — iPhone Music Library (Apple Music / iTunes)
                // This IS "the device's music library" on iOS.
                // ─────────────────────────────────────────────────────────────
                Section {
                    Button {
                        library.requestAccessAndScan()
                        importSuccess = "Scanning iPhone music library…"
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.dynamicAccent)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "music.note.house.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 20))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("iPhone Music Library")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Your songs synced via iTunes, Finder, or Apple Music")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Show current access status
                    let status = MPMediaLibrary.authorizationStatus()
                    if status == .denied || status == .restricted {
                        Label("Access denied — tap above to open Settings", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warning)
                    } else if status == .authorized {
                        Label("\(library.allSongs.count) songs in library", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.success)
                    }
                } header: {
                    sectionLabel("Your iPhone's Music")
                } footer: {
                    Text("On iOS, your iPhone's music library is managed by Apple Music / iTunes. Tap above to grant access and scan all songs stored on your device.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // ─────────────────────────────────────────────────────────────
                // MARK: Scan app storage (files transferred via Mac/Finder)
                // ─────────────────────────────────────────────────────────────
                Section {
                    Button {
                        if let docs = FileManager.default
                            .urls(for: .documentDirectory, in: .userDomainMask).first {
                            library.scanSpecificDirectory(docs)
                            importSuccess = "Scanning app storage…"
                        }
                    } label: {
                        importRow(
                            icon: "folder.fill", color: AppTheme.dynamicAccent.opacity(0.85),
                            title: "Scan App Storage",
                            subtitle: "Scans files you've transferred to this app"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionLabel("App Storage")
                } footer: {
                    Text("Files dragged into this app via Finder/Files app (Mac USB or Files → On My iPhone → Lumisound) are stored here. Subfolders are included.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // ─────────────────────────────────────────────────────────────
                // MARK: Import individual files from anywhere
                // ─────────────────────────────────────────────────────────────
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        importRow(
                            icon: "doc.badge.plus", color: AppTheme.dynamicAccent,
                            title: "Import Audio Files",
                            subtitle: "Browse Files app — select any MP3, M4A, FLAC, WAV…"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionLabel("Individual Files")
                } footer: {
                    Text("Navigate to any folder in the Files app (Downloads, iCloud Drive, etc.) and select multiple songs to import.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // ─────────────────────────────────────────────────────────────
                // ─────────────────────────────────────────────────────────────
                // MARK: Cloud Backup
                // ─────────────────────────────────────────────────────────────
                Section {
                    NavigationLink {
                        UploadMusicView()
                    } label: {
                        importRow(
                            icon: "icloud.and.arrow.up",
                            color: AppTheme.dynamicAccent,
                            title: "Cloud Backup & Upload",
                            subtitle: "Upload tracks to your account — restore them anytime"
                        )
                    }
                } header: {
                    sectionLabel("Cloud Storage")
                } footer: {
                    Text("Requires a Lumisound account. Uploaded tracks can be redownloaded to any device after reinstalling.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // ─────────────────────────────────────────────────────────────
                // MARK: Mac / USB transfer instructions
                // ─────────────────────────────────────────────────────────────
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "cable.connector").frame(width: 32).foregroundStyle(.gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer via Mac (USB or WiFi)")
                                .fontWeight(.medium).foregroundStyle(AppTheme.textPrimary)
                            Text("Finder → your iPhone → Files tab → Lumisound → drag files/folders in")
                                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Feedback banner
                if let msg = importSuccess {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppTheme.accent)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(mode: .audioFiles) { urls in
                    showFilePicker = false
                    guard !urls.isEmpty else { return }
                    library.importFiles(urls: urls)
                    importSuccess = "\(urls.count) file\(urls.count == 1 ? "" : "s") imported"
                }
                .ignoresSafeArea()
            }
        }
    }

    private func importRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 32).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium).foregroundStyle(AppTheme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
