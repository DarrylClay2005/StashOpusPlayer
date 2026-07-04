import SwiftUI

/// Manage Now Playing styles — toggle visibility of the 19 built-in styles
/// (Feature: per-user remove/add of styles) and edit/delete user-created
/// custom ones. Reachable from the style picker's manage button.
struct StyleManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryManager
    @ObservedObject private var customStyleStore = CustomStyleStore.shared
    @ObservedObject private var hiddenStylesStore = HiddenStylesStore.shared
    @State private var editingCustomStyle: CustomNowPlayingStyle?

    var body: some View {
        NavigationStack {
            List {
                customStylesSection
                builtinStylesSection
            }
            .navigationTitle("Manage Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingCustomStyle) { style in
                CustomStyleEditorView(style: style, previewSong: nil) { saved in
                    customStyleStore.update(saved)
                }
                .environmentObject(library)
            }
        }
    }

    @ViewBuilder
    private var customStylesSection: some View {
        Section {
            if customStyleStore.styles.isEmpty {
                Text("No custom styles yet — tap \"New Style\" in the picker to create one.")
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
            ForEach(NowPlayingArtworkStyle.allCases) { style in
                Toggle(isOn: Binding(
                    get: { !hiddenStylesStore.isHidden(style.rawValue) },
                    set: { visible in hiddenStylesStore.setHidden(!visible, for: style.rawValue) }
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
