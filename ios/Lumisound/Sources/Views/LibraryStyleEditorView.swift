import SwiftUI

/// Builder/editor for a user-created library row style, with a live preview
/// (row + grid forms) that updates as settings change — every control maps
/// directly to a `CustomLibraryRowStyle` field, rendered by the same
/// `CustomLibraryRowView`/`CustomLibraryGridCellView` used throughout the
/// library.
struct LibraryStyleEditorView: View {
    let previewSong: Song?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var draft: CustomLibraryRowStyle
    private let onSave: (CustomLibraryRowStyle) -> Void

    private static let icons = ["list.bullet.rectangle", "rectangle.grid.1x2", "square.stack",
                                 "rectangle.on.rectangle", "circle.grid.2x2", "list.dash"]

    private var samplePreviewSong: Song {
        previewSong ?? Song(title: "Sample Song", artist: "Sample Artist", album: "Sample Album", duration: 214)
    }

    init(style: CustomLibraryRowStyle, previewSong: Song?, onSave: @escaping (CustomLibraryRowStyle) -> Void) {
        _draft = State(initialValue: style)
        self.previewSong = previewSong
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                nameSection
                layoutSection
                artworkSection
                contentSection
                accentSection
            }
            .navigationTitle("Custom Row Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = draft.name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { draft.name = trimmed }
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Section {
            VStack(spacing: 12) {
                CustomLibraryRowView(song: samplePreviewSong, isCurrent: true, config: draft)
                    .environmentObject(library)
                    .environmentObject(player)
                HStack {
                    CustomLibraryGridCellView(song: samplePreviewSong, isCurrent: false, config: draft)
                        .environmentObject(library)
                        .environmentObject(player)
                        .frame(width: 140)
                    Spacer(minLength: 0)
                }
            }
            .listRowBackground(Color.clear)
        } header: {
            Text("Preview")
        } footer: {
            Text("Row form (top) shows the \"now playing\" look; grid form (bottom) shows the normal look.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Name/Icon

    @ViewBuilder
    private var nameSection: some View {
        Section("Name") {
            TextField("Style name", text: $draft.name)
            Picker("Icon", selection: $draft.iconName) {
                ForEach(Self.icons, id: \.self) { icon in
                    Image(systemName: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var layoutSection: some View {
        Section("Layout") {
            Picker("Form", selection: $draft.layout) {
                ForEach(CustomLibraryRowStyle.Layout.allCases) { layout in
                    Text(layout.label).tag(layout)
                }
            }
            Picker("Density", selection: $draft.density) {
                ForEach(CustomLibraryRowStyle.Density.allCases) { density in
                    Text(density.label).tag(density)
                }
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkSection: some View {
        Section("Artwork") {
            Picker("Shape", selection: $draft.artworkShape) {
                ForEach(CustomLibraryRowStyle.ArtworkShape.allCases) { shape in
                    Text(shape.label).tag(shape)
                }
            }
            if draft.artworkShape == .rounded {
                VStack(alignment: .leading) {
                    Text("Corner Radius: \(Int(draft.artworkCornerRadius))")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    Slider(value: $draft.artworkCornerRadius, in: 0...24, step: 1)
                }
            }
            VStack(alignment: .leading) {
                Text("Size: \(Int(draft.artworkSize))")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                Slider(value: $draft.artworkSize, in: 28...72, step: 2)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        Section("Content") {
            Picker("Title Weight", selection: $draft.titleWeight) {
                ForEach(CustomLibraryRowStyle.TitleWeight.allCases) { weight in
                    Text(weight.label).tag(weight)
                }
            }
            Toggle("Show Subtitle", isOn: $draft.showSubtitle)
            Toggle("Show Duration", isOn: $draft.showDuration)
            if draft.layout == .row {
                Toggle("Show Divider", isOn: $draft.showDivider)
            }
        }
    }

    // MARK: - Accent

    @ViewBuilder
    private var accentSection: some View {
        Section {
            Picker("Usage", selection: $draft.accentUsage) {
                ForEach(CustomLibraryRowStyle.AccentUsage.allCases) { usage in
                    Text(usage.label).tag(usage)
                }
            }
        } header: {
            Text("Now-Playing Accent")
        } footer: {
            Text("Controls how the currently-playing track is highlighted.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
