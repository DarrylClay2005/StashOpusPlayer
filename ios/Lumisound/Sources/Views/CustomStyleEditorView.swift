import SwiftUI

/// Builder/editor for a user-created Now Playing style, with a live
/// preview that updates as settings change — every control maps directly
/// to a `CustomNowPlayingStyle` field, rendered by the same
/// `CustomStyleArtworkView` used in Now Playing itself.
struct CustomStyleEditorView: View {
    let previewSong: Song?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @State private var draft: CustomNowPlayingStyle
    private let onSave: (CustomNowPlayingStyle) -> Void

    private static let icons = ["paintpalette.fill", "sparkles", "star.fill", "heart.fill",
                                "bolt.fill", "moon.stars.fill", "flame.fill", "leaf.fill"]

    init(style: CustomNowPlayingStyle, previewSong: Song?, onSave: @escaping (CustomNowPlayingStyle) -> Void) {
        _draft = State(initialValue: style)
        self.previewSong = previewSong
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                nameSection
                backgroundSection
                coverSection
                borderSection
                shadowSection
                decorationSection
                animationSection
                accentSection
            }
            .navigationTitle("Custom Style")
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
            HStack {
                Spacer()
                CustomStyleArtworkView(song: previewSong, isPlaying: true, config: draft)
                    .environmentObject(library)
                    .scaleEffect(0.5)
                    .frame(width: 150, height: 150)
                Spacer()
            }
            .listRowBackground(Color.clear)
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

    // MARK: - Background

    @ViewBuilder
    private var backgroundSection: some View {
        Section("Background") {
            Picker("Type", selection: $draft.backgroundKind) {
                ForEach(CustomNowPlayingStyle.BackgroundKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            if draft.backgroundKind == .solid {
                ColorPicker("Color", selection: Binding(
                    get: { draft.backgroundColor1.color },
                    set: { draft.backgroundColor1 = CodableColor($0) }
                ))
            } else if draft.backgroundKind == .gradient {
                ColorPicker("Color 1", selection: Binding(
                    get: { draft.backgroundColor1.color },
                    set: { draft.backgroundColor1 = CodableColor($0) }
                ))
                ColorPicker("Color 2", selection: Binding(
                    get: { draft.backgroundColor2.color },
                    set: { draft.backgroundColor2 = CodableColor($0) }
                ))
            }
        }
    }

    // MARK: - Cover

    @ViewBuilder
    private var coverSection: some View {
        Section("Cover") {
            Picker("Shape", selection: $draft.coverShape) {
                ForEach(CustomNowPlayingStyle.CoverShape.allCases) { shape in
                    Text(shape.label).tag(shape)
                }
            }
            if draft.coverShape == .rounded {
                VStack(alignment: .leading) {
                    Text("Corner Radius: \(Int(draft.cornerRadius))")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    Slider(value: $draft.cornerRadius, in: 0...40, step: 1)
                }
            }
            VStack(alignment: .leading) {
                Text("Size: \(Int(draft.coverSize))")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                Slider(value: $draft.coverSize, in: 120...260, step: 10)
            }
        }
    }

    // MARK: - Border

    @ViewBuilder
    private var borderSection: some View {
        Section("Border") {
            Picker("Style", selection: $draft.borderStyle) {
                ForEach(CustomNowPlayingStyle.BorderStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            if draft.borderStyle != .none {
                Toggle("Use Accent Color", isOn: $draft.borderUsesAccent)
                if !draft.borderUsesAccent {
                    ColorPicker("Color", selection: Binding(
                        get: { draft.borderColor.color },
                        set: { draft.borderColor = CodableColor($0) }
                    ))
                }
            }
        }
    }

    // MARK: - Shadow

    @ViewBuilder
    private var shadowSection: some View {
        Section("Shadow") {
            Picker("Style", selection: $draft.shadowStyle) {
                ForEach(CustomNowPlayingStyle.ShadowStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
        }
    }

    // MARK: - Decoration

    @ViewBuilder
    private var decorationSection: some View {
        Section {
            Picker("Effect", selection: $draft.decoration) {
                ForEach(CustomNowPlayingStyle.Decoration.allCases) { deco in
                    Label(deco.label, systemImage: deco.iconName).tag(deco)
                }
            }
        } header: {
            Text("Decoration")
        } footer: {
            if draft.decoration == .waveform {
                Text("Reacts to the actual audio in real time — silent/still when paused.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Animation

    @ViewBuilder
    private var animationSection: some View {
        Section("Cover Animation") {
            Picker("Animation", selection: $draft.coverAnimation) {
                ForEach(CustomNowPlayingStyle.CoverAnimation.allCases) { anim in
                    Text(anim.label).tag(anim)
                }
            }
            if draft.coverAnimation != .none {
                VStack(alignment: .leading) {
                    Text("Speed: \(String(format: "%.1f", draft.animationSpeed))x")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    Slider(value: $draft.animationSpeed, in: 0.5...2.0, step: 0.1)
                }
            }
        }
    }

    // MARK: - Accent

    @ViewBuilder
    private var accentSection: some View {
        Section("Accent Color") {
            Picker("Source", selection: $draft.accentSource) {
                ForEach(CustomNowPlayingStyle.AccentSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            if draft.accentSource == .custom {
                ColorPicker("Color", selection: Binding(
                    get: { draft.customAccentColor.color },
                    set: { draft.customAccentColor = CodableColor($0) }
                ))
            }
        }
    }
}
