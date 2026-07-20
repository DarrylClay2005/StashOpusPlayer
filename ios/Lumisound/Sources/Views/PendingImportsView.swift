import SwiftUI

// MARK: - PendingImportsView
//
// Visibility into the background download-recovery pipeline (see
// StreamingService+PendingDownloads.swift): what's currently sitting on the
// bridge finished-but-unfetched, and what was just auto-imported this
// session and where it landed. Auto-import keeps running exactly as before
// (launch/foreground/BGAppRefreshTask/silent push) — this screen doesn't
// replace that, it just makes it visible, and offers a manual per-item or
// "Import All" as a convenience for anyone who doesn't want to wait for the
// next automatic trigger.

struct PendingImportsView: View {
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var library: LibraryManager

    @State private var pending: [StreamingService.PendingDownloadInfo] = []
    @State private var isLoading = false
    @State private var isImportingAll = false
    /// Per-row folder override, keyed by job_id — pre-filled from
    /// `entry.destination_folder` the first time a row appears, then left
    /// alone so the picker doesn't reset itself out from under a change the
    /// user just made on refresh.
    @State private var folderOverrides: [String: String] = [:]
    @State private var importingJobIDs: Set<String> = []

    var body: some View {
        List {
            if pending.isEmpty && streaming.recentImports.isEmpty && !isLoading {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("Nothing waiting")
                            .font(AppTheme.bodyFont(size: 15))
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Downloads that finish while the app is closed show up here automatically.")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending, id: \.job_id) { entry in
                        pendingRow(entry)
                    }
                    Button {
                        Task { await importAll() }
                    } label: {
                        HStack {
                            Spacer()
                            if isImportingAll {
                                ProgressView()
                            } else {
                                Text("Import All")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isImportingAll || !importingJobIDs.isEmpty)
                } header: {
                    Text("Pending (\(pending.count))")
                }
            }

            if !streaming.recentImports.isEmpty {
                Section {
                    ForEach(streaming.recentImports) { item in
                        recentImportRow(item)
                    }
                } header: {
                    Text("Recently Imported")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Pending Imports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Rows

    @ViewBuilder
    private func pendingRow(_ entry: StreamingService.PendingDownloadInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? entry.filename)
                    .font(AppTheme.bodyFont(size: 15))
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let artist = entry.artist, !artist.isEmpty {
                    Text(artist)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            HStack {
                DownloadFolderPicker(folderName: folderBinding(for: entry))
                Spacer()
                Button {
                    Task { await importNow(entry) }
                } label: {
                    if importingJobIDs.contains(entry.job_id) {
                        ProgressView()
                    } else {
                        Label("Import Now", systemImage: "tray.and.arrow.down")
                            .font(AppTheme.bodyFont(size: 13))
                    }
                }
                .disabled(importingJobIDs.contains(entry.job_id) || isImportingAll)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func recentImportRow(_ item: StreamingService.RecentImport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text((item.destinationFolder?.isEmpty == false ? item.destinationFolder : nil) ?? "Imported Music")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Text(item.importedAt, style: .relative)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: Actions

    private func folderBinding(for entry: StreamingService.PendingDownloadInfo) -> Binding<String> {
        Binding(
            get: { folderOverrides[entry.job_id] ?? entry.destination_folder ?? "" },
            set: { folderOverrides[entry.job_id] = $0 }
        )
    }

    private func refresh() async {
        isLoading = true
        pending = await streaming.fetchPendingDownloads()
        isLoading = false
    }

    private func importNow(_ entry: StreamingService.PendingDownloadInfo) async {
        importingJobIDs.insert(entry.job_id)
        defer { importingJobIDs.remove(entry.job_id) }
        let override = folderOverrides[entry.job_id]
        guard await streaming.importPendingDownload(entry, folderOverride: override) else {
            ToastCenter.shared.show("Couldn't import \"\(entry.title ?? entry.filename)\"", category: .error)
            return
        }
        await library.scanLocalDocumentsAsync()
        await refresh()
    }

    private func importAll() async {
        isImportingAll = true
        defer { isImportingAll = false }
        await streaming.reconcilePendingDownloads()
        await refresh()
    }
}
