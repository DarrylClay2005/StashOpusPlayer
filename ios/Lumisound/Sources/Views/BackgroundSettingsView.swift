import SwiftUI
import PhotosUI
import UIKit

// MARK: - BackgroundSettingsView

struct BackgroundSettingsView: View {
    @EnvironmentObject var bg: BackgroundService
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    var body: some View {
        List {
            // MARK: Status + Start/Stop button
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bg.isEnabled && bg.isActive ? "Gallery Running" : bg.images.isEmpty ? "No images added" : "Gallery Paused")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bg.isEnabled && bg.isActive ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                        if !bg.images.isEmpty {
                            Text("\(bg.images.count) image\(bg.images.count == 1 ? "" : "s") loaded")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    Spacer()
                    if !bg.images.isEmpty {
                        Button {
                            if bg.isEnabled && bg.isActive {
                                bg.isEnabled = false
                                bg.stopShuffling()
                                bg.saveSettings()
                            } else {
                                bg.isEnabled = true
                                bg.saveSettings()
                                bg.startShuffling()
                            }
                        } label: {
                            Text(bg.isEnabled && bg.isActive ? "Stop" : "Start")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(bg.isEnabled && bg.isActive ? AppTheme.error : AppTheme.dynamicAccent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: bg.isEnabled && bg.isActive)
                    }
                }
                .padding(.vertical, 4)

                // Preview current background image
                if bg.isEnabled, !bg.images.isEmpty {
                    Image(uiImage: bg.images[bg.currentIndex % bg.images.count])
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(10)
                        .blur(radius: bg.isBlurred ? 8 : 0, opaque: true)
                        .opacity(bg.opacity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppTheme.dynamicAccent.opacity(0.4), lineWidth: 1)
                        )
                }
            }

            // MARK: Image Picker Section
            Section("Images (\(bg.images.count) saved)") {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 50,
                    matching: .images
                ) {
                    HStack {
                        Label("Add from Photo Library", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if isLoadingPhotos {
                            ProgressView()
                                .tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .onChange(of: selectedItems) { items in
                    guard !items.isEmpty else { return }
                    isLoadingPhotos = true
                    Task {
                        var loaded: [UIImage] = []
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                loaded.append(image)
                            }
                        }
                        await MainActor.run {
                            if !loaded.isEmpty {
                                bg.addImages(loaded)
                            }
                            selectedItems = []
                            isLoadingPhotos = false
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
                                    .overlay(alignment: .bottomLeading) {
                                        if i == bg.currentIndex && bg.isEnabled {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppTheme.dynamicAccent)
                                                .background(Color.black.opacity(0.5), in: Circle())
                                                .font(.caption)
                                                .padding(3)
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Show settings as soon as images exist (not just when enabled)
            if !bg.images.isEmpty {

                // MARK: Shuffle Interval Section
                Section("Shuffle Interval") {
                    Picker("Interval", selection: $bg.shuffleIntervalSeconds) {
                        ForEach(BackgroundService.intervalPresets, id: \.seconds) { p in
                            Text(p.label).tag(p.seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.dynamicAccent)
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
                                        bg.animation == anim ? AppTheme.dynamicAccent : AppTheme.surface,
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
                            .foregroundStyle(AppTheme.dynamicAccent)
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
                            .tint(AppTheme.dynamicAccent)
                            .onChange(of: bg.opacity) { _ in bg.saveSettings() }
                    }

                    Toggle("Blur Background", isOn: $bg.isBlurred)
                        .tint(AppTheme.dynamicAccent)
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
