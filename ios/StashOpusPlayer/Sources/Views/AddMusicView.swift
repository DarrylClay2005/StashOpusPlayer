import SwiftUI

struct AddMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager

    @State private var showFilePicker = false
    @State private var importSuccess: String? = nil

    // MARK: Preset locations (computed fresh each time the view appears)

    private var presetLocations: [URL] {
        var urls: [URL] = []
        let fm = FileManager.default
        if let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            urls.append(dl)
        }
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs)
        }
        return urls.filter { fm.fileExists(atPath: $0.path) }
    }

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

                // MARK: Scan a Preset Location
                Section {
                    ForEach(presetLocations, id: \.path) { url in
                        Button {
                            library.scanSpecificDirectory(url)
                            importSuccess = "Scanning \(url.lastPathComponent)…"
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .frame(width: 32)
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Scan a Location")
                } footer: {
                    Text("Tap a location to scan it for audio files immediately. No permission dialog required.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                // MARK: Individual Files
                Section {
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
                } header: {
                    Text("Individual Files")
                } footer: {
                    Text("Select multiple files from any folder by navigating to it and tapping each file.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
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
