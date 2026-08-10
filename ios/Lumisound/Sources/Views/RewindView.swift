import SwiftUI

// MARK: - RewindView
//
// A shareable "Rewind" recap of the user's listening. Three modes:
//  - All Time: the original lifetime card, built from /user/stats.
//  - This Year: a proper "Wrapped"-style annual recap, built from
//    /user/stats/year-in-review (calendar-year-bucketed — /user/stats has
//    no year dimension at all, it's lifetime-only) with a couple of extra
//    stats the lifetime card has no room/data for (distinct artists/tracks,
//    peak listening day, average BPM).
//  - This Month: same idea as This Year but bucketed to the current
//    calendar month via /user/stats/month-in-review, for a recap that
//    refreshes far more often than the annual one.
// Any card is rendered to an image via ImageRenderer (iOS 16+) and
// shared through the system share sheet.

private enum RewindMode: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case thisMonth = "This Month"
    case thisYear = "This Year"
    var id: String { rawValue }
}

struct RewindView: View {
    @EnvironmentObject private var account: AccountService

    @State private var mode: RewindMode = .allTime
    @State private var shareImage: UIImage?
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Picker("Rewind range", selection: $mode) {
                    ForEach(RewindMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                recapCard
                    .frame(maxWidth: 360)

                Button {
                    renderAndShare()
                } label: {
                    Label("Share My Rewind", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.dynamicAccent)
                .disabled(!hasDataForCurrentMode)
            }
            .padding()
        }
        .navigationTitle("Your Rewind")
        .navigationBarTitleDisplayMode(.inline)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .task { await loadDataIfNeeded(for: mode) }
        .onChange(of: mode) { newMode in
            Task { await loadDataIfNeeded(for: newMode) }
        }
        .sheet(isPresented: $showShare) {
            if let img = shareImage {
                RewindShareSheet(items: [img])
            }
        }
    }

    private var hasDataForCurrentMode: Bool {
        switch mode {
        case .allTime: return account.stats != nil
        case .thisMonth: return account.monthInReview != nil
        case .thisYear: return account.yearInReview != nil
        }
    }

    private func loadDataIfNeeded(for mode: RewindMode) async {
        switch mode {
        case .allTime:
            if account.stats == nil { await account.fetchStats() }
        case .thisMonth:
            if account.monthInReview == nil { await account.fetchMonthInReview() }
        case .thisYear:
            if account.yearInReview == nil { await account.fetchYearInReview() }
        }
    }

    // MARK: Card (also what gets rendered to an image)

    @ViewBuilder
    private var recapCard: some View {
        switch mode {
        case .allTime: allTimeCard
        case .thisMonth: monthCard
        case .thisYear: yearCard
        }
    }

    private var monthCard: some View {
        cardShell(title: "LUMISOUND \(account.monthInReview?.displayName.uppercased() ?? "") REWIND") {
            if let m = account.monthInReview {
                if m.totalPlays == 0 {
                    Text("No listening activity yet this month.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.vertical, 20)
                } else {
                    bigStat(value: "\(m.totalPlays)", label: "songs played")
                    bigStat(value: formattedTime(m.totalListenSeconds), label: "time listened")

                    HStack(spacing: 24) {
                        smallStat(value: "\(m.distinctArtists)", label: "artists")
                        smallStat(value: "\(m.distinctTracks)", label: "tracks")
                        if let bpm = m.averageBpm {
                            smallStat(value: "\(Int(bpm.rounded()))", label: "avg bpm")
                        }
                    }

                    if !m.topArtists.isEmpty {
                        listBlock(title: "Top Artists",
                                  rows: m.topArtists.prefix(5).map { "\($0.artist)" })
                    }
                    if !m.topTracks.isEmpty {
                        listBlock(title: "Top Songs",
                                  rows: m.topTracks.prefix(5).map { $0.title })
                    }
                    if let peak = m.peakDay {
                        listBlock(title: "Peak Day", rows: ["\(peak.date) — \(peak.plays) plays"])
                    }
                }
            } else {
                loadingRow
            }
        }
    }

    private var allTimeCard: some View {
        cardShell(title: "LUMISOUND REWIND") {
            if let s = account.stats {
                bigStat(value: "\(s.totalPlays)", label: "songs played")
                bigStat(value: formattedTime(s.totalListenSeconds), label: "time listened")

                if !s.topArtists.isEmpty {
                    listBlock(title: "Top Artists",
                              rows: s.topArtists.prefix(5).map { "\($0.artist)" })
                }
                if !s.topTracks.isEmpty {
                    listBlock(title: "Top Songs",
                              rows: s.topTracks.prefix(5).map { $0.title })
                }
            } else {
                loadingRow
            }
        }
    }

    private var yearCard: some View {
        cardShell(title: "LUMISOUND \(account.yearInReview.map { String($0.year) } ?? "") REWIND") {
            if let y = account.yearInReview {
                if y.totalPlays == 0 {
                    Text("No listening activity yet this year.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.vertical, 20)
                } else {
                    bigStat(value: "\(y.totalPlays)", label: "songs played")
                    bigStat(value: formattedTime(y.totalListenSeconds), label: "time listened")

                    HStack(spacing: 24) {
                        smallStat(value: "\(y.distinctArtists)", label: "artists")
                        smallStat(value: "\(y.distinctTracks)", label: "tracks")
                        if let bpm = y.averageBpm {
                            smallStat(value: "\(Int(bpm.rounded()))", label: "avg bpm")
                        }
                    }

                    if !y.topArtists.isEmpty {
                        listBlock(title: "Top Artists",
                                  rows: y.topArtists.prefix(5).map { "\($0.artist)" })
                    }
                    if !y.topTracks.isEmpty {
                        listBlock(title: "Top Songs",
                                  rows: y.topTracks.prefix(5).map { $0.title })
                    }
                    if let peak = y.peakDay {
                        listBlock(title: "Peak Day", rows: ["\(peak.date) — \(peak.plays) plays"])
                    }
                }
            } else {
                loadingRow
            }
        }
    }

    private var loadingRow: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private func cardShell<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "music.note.list")
                Text(title)
                    .kerning(2)
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))

            content()

            Text("Lumisound")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.dynamicAccent, AppTheme.dynamicAccent.opacity(0.55), .black.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func bigStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func smallStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func listBlock(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.85))
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, name in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, alignment: .leading)
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content:
            recapCard
                .frame(width: 360)
                .environmentObject(account)
        )
        renderer.scale = UIScreen.main.scale
        if let ui = renderer.uiImage {
            shareImage = ui
            showShare = true
        }
    }
}

// MARK: - Share sheet wrapper

struct RewindShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
