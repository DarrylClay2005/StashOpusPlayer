import Foundation
import SwiftUI

// MARK: - AdminDashboardView
//
// The in-app counterpart to the standalone /admin web dashboard (see
// main.py's _ADMIN_DASHBOARD_HTML) — same three endpoints
// (/admin/api/overview, /admin/api/download-jobs, /admin/api/errors), same
// data, native UI instead of a browser tab.
//
// Access control is enforced server-side (check_admin_or_operator only
// accepts the hardcoded operator account's own JWT or the separate
// ADMIN_TOKEN secret — see that function's doc comment in main.py) — no
// admin credential is embedded in this app at all. The `operatorUserID`
// check here is purely a client-side UX gate (don't even show the entry
// point / don't render a confusing "everything failed" screen for anyone
// else) — removing it would only hide a menu item, never grant access,
// since the server enforces the real boundary independently.
struct AdminDashboardView: View {
    static let operatorUserID = "ca8a4c53-5603-472e-9287-5fb879f28090"

    @EnvironmentObject private var account: AccountService
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if account.currentUser?.id == Self.operatorUserID {
                dashboard
            } else {
                ContentUnavailableFallback()
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private var dashboard: some View {
        List {
            Section("Overview") {
                if let o = account.adminOverview {
                    overviewGrid(o)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }

            Section("Download Jobs (last 24h)") {
                if let o = account.adminOverview {
                    ForEach(o.downloadJobs24h.sorted(by: { $0.key < $1.key }), id: \.key) { status, count in
                        HStack {
                            Text(status.capitalized)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }

            Section("Recent Download Jobs") {
                if account.adminDownloadJobs.isEmpty {
                    Text("No jobs recorded.")
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(account.adminDownloadJobs) { job in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(job.title?.isEmpty == false ? job.title! : job.sourceId)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                statusPill(job.status)
                            }
                            if let err = job.errorMessage, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                            Text([job.source, job.createdAt].compactMap { $0 }.joined(separator: " — "))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }

            Section("Recent Errors") {
                if account.adminErrors.isEmpty {
                    Text("No errors logged.")
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(account.adminErrors) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                Spacer()
                                if let ts = entry.timestamp {
                                    Text(ts)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func overviewGrid(_ o: AdminOverview) -> some View {
        let items: [(String, String)] = [
            ("Users", "\(o.userCount)"),
            ("Music Files", "\(o.musicFileCount)"),
            ("Storage Used", formattedBytes(o.musicBytes)),
            ("Disk Free", o.disk.map { formattedBytes(Int($0.freeBytes)) } ?? "n/a"),
            ("Errors (24h)", "\(o.recentErrorCount24h)"),
            ("yt-dlp Slots", "\(o.concurrency.ytdlpAvailable)/\(o.concurrency.ytdlpMax) free"),
            ("Transcode Slots", "\(o.concurrency.transcodeAvailable)/\(o.concurrency.transcodeMax) free"),
            ("yt-dlp Version", o.ytDlpVersion),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusPill(_ status: String) -> some View {
        let color: Color = status == "completed" ? .green : (status == "failed" || status == "error" ? .red : AppTheme.textSecondary)
        return Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func formattedBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func refresh() async {
        guard account.currentUser?.id == Self.operatorUserID else { return }
        isRefreshing = true
        async let overview: () = account.fetchAdminOverview()
        async let jobs: () = account.fetchAdminDownloadJobs()
        async let errors: () = account.fetchAdminErrors()
        _ = await (overview, jobs, errors)
        isRefreshing = false
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Not Available")
                .font(.headline)
            Text("This screen is only available to the app's operator account.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
