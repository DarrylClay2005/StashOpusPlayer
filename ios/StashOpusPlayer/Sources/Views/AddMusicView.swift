import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AddMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var folderService: MusicFolderService

    @State private var showFolderInstructions = false
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
                        importRow(
                            icon: "music.note.house.fill", color: .pink,
                            title: "Scan Apple Music Library",
                            subtitle: "Access songs synced via iTunes or Apple Music"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Music Folder (Files App)
                // iOS folder-picker how-to: you must navigate INTO the target folder,
                // then tap "Open" to register it. Tapping a folder in the list navigates
                // into it — that's intentional. Once you're inside it, tap Open.
                Section {
                    Button {
                        showFolderInstructions = true
                    } label: {
                        importRow(
                            icon: "folder.fill", color: .yellow,
                            title: "Watch a Folder",
                            subtitle: "All audio files inside will be scanned automatically"
                        )
                    }
                    .buttonStyle(.plain)
                    .alert("How to select your music folder", isPresented: $showFolderInstructions) {
                        Button("Open Folder Picker") { showFolderPicker = true }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "In the file browser:\n\n" +
                            "1. Navigate INTO the folder that holds your music " +
                            "(e.g. tap \"Downloads\" to enter it).\n\n" +
                            "2. Once you are inside that folder, tap \"Open\" " +
                            "in the top bar — this registers it as your music folder.\n\n" +
                            "Tip: the Open button selects the folder you are currently viewing."
                        )
                    }

                    ForEach(folderService.watchedFolders) { folder in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName)
                                    .font(.subheadline).foregroundStyle(AppTheme.textPrimary)
                                Text("\(folder.trackCount) tracks · Watching")
                                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button { folderService.removeFolder(id: folder.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Music Folder (Files App)")
                } footer: {
                    Text("Open the file browser, navigate INTO your music folder, then tap \"Open\" to set it.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                // MARK: Individual Files
                Section("Individual Files") {
                    Button {
                        showFilePicker = true
                    } label: {
                        importRow(
                            icon: "doc.badge.plus", color: .blue,
                            title: "Import Audio Files",
                            subtitle: "Navigate to any folder, select one or more songs"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Finder / USB
                Section("Finder / USB") {
                    HStack(spacing: 12) {
                        Image(systemName: "cable.connector")
                            .frame(width: 32).foregroundStyle(.gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect iPhone to Mac")
                                .fontWeight(.medium).foregroundStyle(AppTheme.textPrimary)
                            Text("Finder → iPhone → Files → StashOpusPlayer → drag files in")
                                .font(.caption).foregroundStyle(AppTheme.textSecondary)
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
            // Folder picker — navigate INTO your target folder, then tap Open
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker(mode: .folder) { urls in
                    showFolderPicker = false
                    guard let url = urls.first else { return }
                    do {
                        try folderService.addFolder(url: url)
                        library.scanWatchedFolders(using: folderService)
                        importSuccess = "'\(url.lastPathComponent)' is now being watched"
                    } catch {
                        importSuccess = "Could not add folder: \(error.localizedDescription)"
                    }
                }
                .ignoresSafeArea()
            }
            // Individual file picker — navigate to any folder, select audio files
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
            Image(systemName: icon)
                .frame(width: 32).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium).foregroundStyle(AppTheme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
