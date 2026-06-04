import SwiftUI
import PhotosUI
import UIKit

// MARK: - BackgroundSettingsView

struct BackgroundSettingsView: View {
    @EnvironmentObject var bg: BackgroundService
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        List {
            // MARK: Enable Toggle
            Section {
                Toggle("Enable Gallery Background", isOn: $bg.isEnabled)
                    .tint(AppTheme.accent)
                    .onChange(of: bg.isEnabled) { _ in
                        bg.saveSettings()
                        if bg.isEnabled {
                            bg.startShuffling()
                        } else {
                            bg.stopShuffling()
                        }
                    }
            }

            if bg.isEnabled {

                // MARK: Persistence note
                Section {
                    Label(
                        "Images are saved to your device and restored on next launch.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
                }

                // MARK: Image Picker Section
                Section("Images (\(bg.images.count) saved)") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 50,
                        matching: .images
                    ) {
                        Label("Select from Gallery (\(bg.images.count) saved)", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .onChange(of: selectedItems) { items in
                        Task {
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run { bg.addImages([image]) }
                                }
                            }
                            await MainActor.run {
                                selectedItems = []
                                if bg.isEnabled { bg.startShuffling() }
                            }
                        }
                    }

                    if !bg.images.isEmpty {
                        Button(role: .destructive) {
                            bg.clearAll()
                        } label: {
                            Label("Clear All Images", systemImage: "trash")
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(bg.images.indices, id: \.self) { i in
                                    Image(uiImage: bg.images[i])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                bg.removeImage(at: i)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white)
                                                    .background(Color.black.opacity(0.5), in: Circle())
                                                    .font(.caption)
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: Shuffle Interval Section
                Section("Shuffle Interval") {
                    Picker("Interval", selection: $bg.shuffleIntervalSeconds) {
                        ForEach(BackgroundService.intervalPresets, id: \.seconds) { p in
                            Text(p.label).tag(p.seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.accent)
                    .onChange(of: bg.shuffleIntervalSeconds) { _ in
                        bg.saveSettings()
                        bg.startShuffling()
                    }
                }

                // MARK: Animation Section
                Section("Transition Animation") {
                    LazyVGrid(
                        columns: Array(repeating: .init(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(BackgroundAnimation.allCases) { anim in
                            VStack(spacing: 4) {
                                Image(systemName: anim.sfSymbol)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        bg.animation == anim ? AppTheme.accent : AppTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(
                                        bg.animation == anim ? .white : AppTheme.textSecondary
                                    )
                                Text(anim.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .onTapGesture {
                                bg.animation = anim
                                bg.saveSettings()
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // MARK: Preview Section
                Section {
                    Button {
                        bg.nextImage()
                    } label: {
                        Label("Preview Next Image", systemImage: "photo.on.rectangle")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .disabled(bg.images.count < 2)
                }

                // MARK: Appearance Section
                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Opacity")
                            Spacer()
                            Text(String(format: "%.0f%%", bg.opacity * 100))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Slider(value: $bg.opacity, in: 0.05...0.8)
                            .tint(AppTheme.accent)
                            .onChange(of: bg.opacity) { _ in bg.saveSettings() }
                    }

                    Toggle("Blur Background", isOn: $bg.isBlurred)
                        .tint(AppTheme.accent)
                        .onChange(of: bg.isBlurred) { _ in bg.saveSettings() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Gallery Background")
        .navigationBarTitleDisplayMode(.inline)
    }
}
