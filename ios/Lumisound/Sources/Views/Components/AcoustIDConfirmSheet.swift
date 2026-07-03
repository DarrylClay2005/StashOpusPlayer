import SwiftUI

/// Attaches the "Identify Track" confirmation sheet, driven by
/// `AcoustIDConfirmCenter.shared.pending` — mount once near the root
/// (alongside `ToastOverlay`) so any screen's song context menu can trigger it.
struct AcoustIDConfirmModifier: ViewModifier {
    @ObservedObject private var center = AcoustIDConfirmCenter.shared
    @EnvironmentObject private var library: LibraryManager

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { center.pending },
            set: { center.pending = $0 }
        )) { pending in
            AcoustIDConfirmSheet(pending: pending)
                .environmentObject(library)
        }
    }
}

extension View {
    func acoustIDConfirmSheet() -> some View {
        modifier(AcoustIDConfirmModifier())
    }
}

private struct AcoustIDConfirmSheet: View {
    let pending: AcoustIDConfirmCenter.Pending
    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Identified from this track's audio. Apply the suggested metadata?")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                VStack(alignment: .leading, spacing: 14) {
                    comparisonRow(label: "Title", current: pending.currentTitle, suggested: pending.match.title)
                    comparisonRow(label: "Artist", current: pending.currentArtist, suggested: pending.match.artist ?? "Unknown Artist")
                    if let album = pending.match.album, !album.isEmpty {
                        comparisonRow(label: "Album", current: "", suggested: album)
                    }
                }
                .padding(16)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Match confidence: \(Int((pending.match.score * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Button {
                    library.applyMetadataCorrection(
                        songID: pending.songID,
                        title: pending.match.title,
                        artist: pending.match.artist,
                        album: pending.match.album
                    )
                    dismiss()
                } label: {
                    Text("Apply")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.dynamicAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }

                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(20)
            .navigationTitle("Identify Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func comparisonRow(label: String, current: String, suggested: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            if !current.isEmpty && current != suggested {
                Text(current)
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text(suggested)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}
