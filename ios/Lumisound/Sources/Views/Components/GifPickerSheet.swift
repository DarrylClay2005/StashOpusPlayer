import SwiftUI

// MARK: - GifPickerSheet
//
// Alternative to `PhotosPicker` for avatar/banner uploads — searches GIPHY
// (via the bridge's `/api/gif-search*` proxy) for a user who'd rather pick an
// animated GIF than a photo from their own gallery. Grid previews are shown
// through `AsyncImage`, which only ever renders a static frame — deliberately
// NOT decoded as animated here (unlike the actual uploaded result, which
// does animate via `AnimatedImageView` once applied): a grid of a few dozen
// simultaneously-animating GIFs would be exactly the kind of avoidable
// per-cell cost this app's redesign already had to fix elsewhere.
struct GifPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Raw GIF bytes for whatever the user picked — ready to hand straight
    /// to `uploadAvatarData(_:)`/`uploadBannerData(_:)`.
    let onPick: (Data) -> Void

    @State private var query = ""
    @State private var results: [GifSearchResult] = []
    @State private var isLoading = false
    @State private var isDownloading = false
    @State private var hasSearchedOnce = false
    @State private var searchTask: Task<Void, Never>? = nil
    /// Guards against out-of-order completions: the initial `.task` (loading
    /// trending) and a debounced search both call `runSearch()`, and nothing
    /// stopped the *slower* of the two from overwriting `results` with its
    /// (now stale) answer after a faster, more recent call already applied
    /// its own — visibly "search shows results that don't match what I
    /// typed" when trending happened to finish last. Each `runSearch()` call
    /// captures its own generation and only applies its results if nothing
    /// newer has started since.
    @State private var searchGeneration = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && hasSearchedOnce && !isLoading {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(results) { result in
                                gifCell(result)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .overlay {
                if isLoading && results.isEmpty {
                    ProgressView().tint(AppTheme.dynamicAccent)
                }
            }
            .overlay {
                if isDownloading {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView().tint(.white)
                    }
                }
            }
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("Choose a GIF")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search GIFs")
            .onChange(of: query) { _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await runSearch()
                }
            }
            .task { await runSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func gifCell(_ result: GifSearchResult) -> some View {
        Button {
            pick(result)
        } label: {
            AsyncImage(url: URL(string: result.previewURL ?? result.gifURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(AppTheme.surface).overlay(
                        Image(systemName: "photo").foregroundStyle(AppTheme.textSecondary)
                    )
                default:
                    Rectangle().fill(AppTheme.surface).overlay(ProgressView())
                }
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "GIF search isn't available right now." : "No GIFs found for \"\(query)\".")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() async {
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let fetched = trimmed.isEmpty ? await GifSearchService.trending() : await GifSearchService.search(query: trimmed)
        // A newer call already started (and will apply its own results and
        // flip these flags itself) — discard this now-stale answer instead
        // of overwriting whatever it already showed.
        guard generation == searchGeneration else { return }
        results = fetched
        isLoading = false
        hasSearchedOnce = true
    }

    private func pick(_ result: GifSearchResult) {
        guard !isDownloading else { return }
        isDownloading = true
        Task {
            defer { isDownloading = false }
            if let data = await GifSearchService.downloadData(for: result) {
                onPick(data)
                dismiss()
            }
        }
    }
}
