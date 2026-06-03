import SwiftUI
import UniformTypeIdentifiers

struct AddMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var folderService: MusicFolderService

    @State private var isFileImporterPresented = false
    @State private var isFolderPickerPresented = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: Apple Music Library
                Section("Apple Music / iTunes Library") {
                    Button {
                        library.requestAccessAndScan()
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
                        isFolderPickerPresented = true
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

                    // Watched folders list with remove option
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
                        isFileImporterPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .frame(width: 32)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Audio Files")
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Select individual MP3, FLAC, M4A, WAV or other audio files")
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
                            Text("Open Finder → iPhone → Files → StashOpusPlayer → drag files in")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
            // Folder picker — uses .folder UTType so the system shows a directory browser
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    try? folderService.addFolder(url: url)
                    library.scanWatchedFolders(using: folderService)
                }
            }
            // Individual file picker
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    library.importFiles(urls: urls)
                }
            }
        }
    }
}
