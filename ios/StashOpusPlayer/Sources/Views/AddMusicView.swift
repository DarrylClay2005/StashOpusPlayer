import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AddMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var folderService: MusicFolderService

    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var importSuccess: String? = nil

    var body: some View {
        NavigationStack {
            List {
                // MARK: Apple Music Library
                Section("Apple Music / iTunes Library") {
                    Button {
                        library.requestAccessAndScan()
                        importSuccess = "Scanning Apple Music library…"
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note.house.fill")
                                .frame(width: 32)
                                .foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Apple Music Library")
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Access songs synced via iTunes or Apple Music")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Music Folder (Files App)
                Section("Music Folder (Files App)") {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .frame(width: 32)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Music Folder")
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Pick a folder — all audio files inside will be added")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(folderService.watchedFolders) { folder in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("\(folder.trackCount) tracks · Added")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                folderService.removeFolder(id: folder.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: Individual Files
                Section("Individual Files") {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .frame(width: 32)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Audio Files")
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Select MP3, FLAC, M4A, WAV or other audio files")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Finder / USB
                Section("Finder / USB") {
                    HStack(spacing: 12) {
                        Image(systemName: "cable.connector")
                            .frame(width: 32)
                            .foregroundStyle(.gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect iPhone to Mac")
                                .fontWeight(.medium)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Finder → iPhone → Files → StashOpusPlayer → drag files in")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                // MARK: Import feedback
                if let msg = importSuccess {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                    }
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
            // MARK: Folder picker — security-scoped URL, handled by MusicFolderService
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker(mode: .folder) { urls in
                    showFolderPicker = false
                    guard let url = urls.first else { return }
                    do {
                        try folderService.addFolder(url: url)
                        library.scanWatchedFolders(using: folderService)
                        importSuccess = "Folder '\(url.lastPathComponent)' added successfully"
                    } catch {
                        importSuccess = "Could not add folder: \(error.localizedDescription)"
                    }
                }
                .ignoresSafeArea()
            }
            // MARK: Audio file picker — files copied to app sandbox (asCopy: true), no scoped access needed
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
}
