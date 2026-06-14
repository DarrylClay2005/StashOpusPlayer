import SwiftUI

struct CacheManagerView: View {

    @EnvironmentObject private var cacheManager: CacheManagerService
    @State private var showClearArtworkConfirm = false
    @State private var showClearTempConfirm = false
    @State private var showClearAllConfirm = false
    @State private var savedBytes: Int64 = 0
    @State private var showSavedBanner = false

    var body: some View {
        List {
            // MARK: Artwork Cache
            Section {
                HStack {
                    Label("Cached Images", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CacheManagerService.formattedSize(cacheManager.artworkCacheSize))
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("\(cacheManager.artworkCacheCount) files")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Button(role: .destructive) {
                    showClearArtworkConfirm = true
                } label: {
                    Label("Clear Artwork Cache", systemImage: "trash")
                        .foregroundStyle(AppTheme.error)
                }
                .disabled(cacheManager.artworkCacheSize == 0)
            } header: {
                sectionHeader("Artwork Cache")
            } footer: {
                Text("Album art thumbnails stored on disk for fast loading. Safe to clear — art is re-fetched as needed.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Temp Download Files
            Section {
                HStack {
                    Label("Temp Downloads", systemImage: "arrow.down.circle.dotted")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(CacheManagerService.formattedSize(cacheManager.tempFilesSize))
                        .font(AppTheme.monoFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Button(role: .destructive) {
                    showClearTempConfirm = true
                } label: {
                    Label("Clear Temp Files", systemImage: "trash")
                        .foregroundStyle(AppTheme.error)
                }
                .disabled(cacheManager.tempFilesSize == 0)
            } header: {
                sectionHeader("Temporary Files")
            } footer: {
                Text("Partial download folders left behind if a stream download was interrupted. Safe to clear when not actively downloading.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Downloaded Music
            Section {
                HStack {
                    Label("Imported Music", systemImage: "music.note")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(CacheManagerService.formattedSize(cacheManager.downloadedMusicSize))
                        .font(AppTheme.monoFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } header: {
                sectionHeader("Downloaded Music")
            } footer: {
                Text("Songs in your app's Documents folder. To remove individual tracks, use the Library view.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Bridge Cache (informational)
            Section {
                HStack {
                    Label("Bridge Server Cache", systemImage: "server.rack")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("Managed on server")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } header: {
                sectionHeader("Remote")
            } footer: {
                Text("yt-dlp streaming cache is stored server-side and managed automatically.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Clear All
            let clearableSize = cacheManager.artworkCacheSize + cacheManager.tempFilesSize
            if clearableSize > 0 {
                Section {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        Label("Clear All Cache", systemImage: "trash")
                            .foregroundStyle(AppTheme.error)
                    }
                } header: {
                    sectionHeader("Actions")
                } footer: {
                    Text("Clears artwork cache and temp downloads in one tap (\(CacheManagerService.formattedSize(clearableSize))). Your downloaded music is never affected.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }

            // MARK: Saved banner
            if showSavedBanner {
                Section {
                    Label("\(CacheManagerService.formattedSize(savedBytes)) freed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Storage & Cache")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if cacheManager.isScanning {
                    ProgressView().tint(AppTheme.dynamicAccent)
                } else {
                    Button {
                        Task { await cacheManager.scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(AppTheme.dynamicAccent)
                }
            }
        }
        .onAppear { cacheManager.scanOnAppear() }
        .confirmationDialog(
            "Clear Artwork Cache?",
            isPresented: $showClearArtworkConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                let freed = cacheManager.artworkCacheSize
                cacheManager.clearArtworkCache()
                flashSavedBanner(bytes: freed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Album art will be re-downloaded as you browse your library.")
        }
        .confirmationDialog(
            "Clear Temp Files?",
            isPresented: $showClearTempConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                let freed = cacheManager.tempFilesSize
                cacheManager.clearTempFiles()
                flashSavedBanner(bytes: freed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Partial download folders will be deleted. Do not clear while a download is in progress.")
        }
        .confirmationDialog(
            "Clear All Cache?",
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                let freed = cacheManager.artworkCacheSize + cacheManager.tempFilesSize
                cacheManager.clearAll()
                flashSavedBanner(bytes: freed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Album art will be re-downloaded as you browse, and any partial download folders will be deleted. Your downloaded music is not affected.")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private func flashSavedBanner(bytes: Int64) {
        guard bytes > 0 else { return }
        savedBytes = bytes
        withAnimation { showSavedBanner = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { showSavedBanner = false }
        }
    }
}
