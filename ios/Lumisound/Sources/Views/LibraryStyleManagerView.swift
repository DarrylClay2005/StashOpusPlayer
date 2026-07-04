import SwiftUI

/// Manage library row styles — toggle visibility of the 4 built-in
/// `SongCardStyle` cases (Feature: per-user remove/add of styles) and
/// edit/delete user-created custom ones. Reachable from the Song Cards
/// picker's manage button in Appearance settings.
struct LibraryStyleManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var customStyleStore = CustomLibraryStyleStore.shared
    @ObservedObject private var hiddenCardStylesStore = HiddenCardStylesStore.shared
    @State private var editingCustomStyle: CustomLibraryRowStyle?

    var body: some View {
        NavigationStack {
            List {
                customStylesSection
                builtinStylesSection
            }
            .navigationTitle("Manage Row Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingCustomStyle) { style in
                LibraryStyleEditorView(style: style, previewSong: library.allSongs.first) { saved in
                    customStyleStore.update(saved)
                }
                .environmentObject(library)
                .environmentObject(player)
            }
        }
    }

    @ViewBuilder
    private var customStylesSection: some View {
        Section {
            if customStyleStore.styles.isEmpty {
                Text("No custom row styles yet — tap \"New Style\" in Appearance to create one.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(customStyleStore.styles) { style in
                    HStack {
                        Image(systemName: style.iconName)
                            .foregroundStyle(AppTheme.dynamicAccent)
                            .frame(width: 24)
                        Text(style.name)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Button {
                            editingCustomStyle = style
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            customStyleStore.remove(id: style.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Your Custom Styles")
        }
        .listRowBackground(AppTheme.surface)
    }

    @ViewBuilder
    private var builtinStylesSection: some View {
        Section {
            ForEach(SongCardStyle.allCases) { style in
                Toggle(isOn: Binding(
                    get: { !hiddenCardStylesStore.isHidden(style.rawValue) },
                    set: { visible in hiddenCardStylesStore.setHidden(!visible, for: style.rawValue) }
                )) {
                    Label(style.displayName, systemImage: style.iconName)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .tint(AppTheme.dynamicAccent)
            }
        } header: {
            Text("Built-In Styles")
        } footer: {
            Text("Turn off any styles you don't want cluttering your picker. They're never deleted — just hidden.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }
}
