import SwiftUI

// MARK: - RewindView
//
// A shareable "Rewind" recap of the user's listening, built from the existing
// /user/stats data (total plays, time listened, top artists/tracks). The card is
// rendered to an image via ImageRenderer (iOS 16+) and shared through the system
// share sheet.

struct RewindView: View {
    @EnvironmentObject private var account: AccountService

    @State private var shareImage: UIImage?
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
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
                .disabled(account.stats == nil)
            }
            .padding()
        }
        .navigationTitle("Your Rewind")
        .navigationBarTitleDisplayMode(.inline)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .task { if account.stats == nil { await account.fetchStats() } }
        .sheet(isPresented: $showShare) {
            if let img = shareImage {
                RewindShareSheet(items: [img])
            }
        }
    }

    // MARK: Card (also what gets rendered to an image)

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "music.note.list")
                Text("LUMISOUND REWIND")
                    .kerning(2)
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))

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
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }

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
