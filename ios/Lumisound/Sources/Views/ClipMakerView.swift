import SwiftUI

/// Attaches the "Make a Clip" sheet, driven by `ClipMakerCenter.shared.pendingSong`
/// — mount once near the root (alongside `.acoustIDConfirmSheet()`) so any
/// screen's song context menu can trigger it.
struct ClipMakerModifier: ViewModifier {
    @ObservedObject private var center = ClipMakerCenter.shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { center.pendingSong },
            set: { center.pendingSong = $0 }
        )) { song in
            ClipMakerView(song: song)
        }
    }
}

extension View {
    func clipMakerSheet() -> some View {
        modifier(ClipMakerModifier())
    }
}

/// Trims a short clip from a local track and shares it — entirely on-device.
/// Deliberately scoped as "export a clip" rather than "set as ringtone":
/// third-party apps can't install a system ringtone directly on iOS, so the
/// honest workflow is exporting an `.m4a` the user can bring into GarageBand
/// (which *can* set ringtones) or a Shortcut of their own. Only offered for
/// songs backed by a real local file — Apple Music library DRM items would
/// just fail the export.
struct ClipMakerView: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Double
    @State private var endTime: Double
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    private let maxClipLength: Double = 60

    init(song: Song) {
        self.song = song
        let end = min(song.duration, 30)
        _startTime = State(initialValue: 0)
        _endTime = State(initialValue: max(1, end))
    }

    var body: some View {
        NavigationStack {
            Form {
                trimSection
                exportSection
            }
            .navigationTitle("Make a Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportedURL {
                    RewindShareSheet(items: [exportedURL])
                }
            }
            .alert("Couldn't Export Clip", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    @ViewBuilder
    private var trimSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Start")
                    Spacer()
                    Text(timeText(startTime))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: $startTime, in: 0...max(1, song.duration - 1), step: 1)
                    .tint(AppTheme.dynamicAccent)
                    .onChange(of: startTime) { newValue in
                        if endTime <= newValue { endTime = min(song.duration, newValue + 1) }
                        if endTime - newValue > maxClipLength { endTime = newValue + maxClipLength }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("End")
                    Spacer()
                    Text(timeText(endTime))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: $endTime, in: 0...song.duration, step: 1)
                    .tint(AppTheme.dynamicAccent)
                    .onChange(of: endTime) { newValue in
                        if newValue <= startTime { startTime = max(0, newValue - 1) }
                        if newValue - startTime > maxClipLength { startTime = newValue - maxClipLength }
                    }
            }
        } header: {
            Text("Trim")
        } footer: {
            Text("Clip length: \(timeText(endTime - startTime)) (max \(Int(maxClipLength))s)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        Section {
            Button {
                exportClip()
            } label: {
                if isExporting {
                    HStack {
                        ProgressView()
                        Text("Exporting…")
                    }
                } else {
                    Label("Export Clip", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExporting || song.url == nil)
        } footer: {
            Text("Exports as an audio file you can share or bring into GarageBand to set as a ringtone — apps can't install a system ringtone directly on iOS.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func exportClip() {
        guard let url = song.url else { return }
        isExporting = true
        Task {
            do {
                let clipURL = try await ClipMakerService.exportClip(from: url, start: startTime, end: endTime)
                exportedURL = clipURL
                isExporting = false
                showShareSheet = true
            } catch {
                isExporting = false
                errorMessage = "This track couldn't be exported — it may be protected content."
            }
        }
    }
}
