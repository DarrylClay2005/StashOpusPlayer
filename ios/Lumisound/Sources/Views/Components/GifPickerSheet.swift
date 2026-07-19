import SwiftUI

// MARK: - GifPickerSheet
//
// Alternative to `PhotosPicker` for avatar/banner uploads — searches GIPHY
// (via the bridge's `/api/gif-search*` proxy) for a user who'd rather pick an
// animated GIF than a photo from their own gallery. Grid previews actually
// animate (via `AnimatedGifPreviewCell` below), and picking one hands off to
// `GifCropView` so the user can reposition/zoom before it's applied, rather
// than always getting whatever `.scaleAspectFill`'s automatic center-crop
// happens to keep.
struct GifPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Width ÷ height of the crop window shown after picking — 1.0 (the
    /// default) for an avatar, something wide for a banner.
    var cropAspect: CGFloat = 1.0
    /// Circular crop guide (avatar) vs. rounded-rectangle (banner).
    var isCircularGuide: Bool = true
    /// Cropped GIF bytes, ready to hand straight to
    /// `uploadAvatarData(_:)`/`uploadBannerData(_:)`.
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
    /// typed" when trending happened to finish last. Each `runSearch()`/
    /// `loadNextPage()` call captures its own generation and only applies
    /// its results if nothing newer (a new search, or a fresher page load)
    /// has started since.
    @State private var searchGeneration = 0

    // MARK: Pagination
    //
    // Both `/api/gif-search` and `/api/gif-search/trending` only ever
    // returned a single flat page (default 30, capped 50) with no way to
    // ask for more — scrolling to the end of the grid just showed nothing
    // further, no matter how many more GIPHY actually had. `currentOffset`/
    // `canLoadMore` below, plus `loadMoreIfNeeded(currentItem:)` triggered
    // from each cell's `.onAppear`, page through the rest server-side now
    // supports (`offset` forwarded straight to GIPHY's own `search`/
    // `trending` endpoints, which support it natively).
    private let pageSize = 30
    @State private var currentOffset = 0
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    /// Set once the user picks a result and its full-resolution bytes have
    /// downloaded — presenting this (as a `.sheet(item:)`) is what hands off
    /// to `GifCropView`.
    @State private var pendingCrop: PendingCrop? = nil

    private struct PendingCrop: Identifiable {
        let id = UUID()
        let data: Data
    }

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
                                    .onAppear { loadMoreIfNeeded(currentItem: result) }
                            }
                        }
                        .padding(8)

                        if isLoadingMore {
                            ProgressView()
                                .tint(AppTheme.dynamicAccent)
                                .padding(.bottom, 16)
                        }
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
        .sheet(item: $pendingCrop) { crop in
            GifCropView(
                sourceData: crop.data,
                cropAspect: cropAspect,
                isCircularGuide: isCircularGuide
            ) { cropped in
                onPick(cropped)
                dismiss()
            }
        }
    }

    private func gifCell(_ result: GifSearchResult) -> some View {
        Button {
            pick(result)
        } label: {
            AnimatedGifPreviewCell(urlString: result.previewURL ?? result.gifURL)
                // Square, matching the crop guide's default avatar aspect —
                // most GIFs are landscape, so a non-square preview cell was
                // showing more of the image than what actually ends up
                // visible once cropped/applied.
                .aspectRatio(1, contentMode: .fill)
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

    /// Fresh search/trending fetch — always page 0, always REPLACES
    /// `results` (as opposed to `loadNextPage()`, which appends). Resets
    /// the pagination state so a new query starts paging from scratch.
    private func runSearch() async {
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        currentOffset = 0
        canLoadMore = true
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let fetched = trimmed.isEmpty
            ? await GifSearchService.trending(limit: pageSize, offset: 0)
            : await GifSearchService.search(query: trimmed, limit: pageSize, offset: 0)
        // A newer call already started (and will apply its own results and
        // flip these flags itself) — discard this now-stale answer instead
        // of overwriting whatever it already showed.
        guard generation == searchGeneration else { return }
        results = fetched
        currentOffset = fetched.count
        canLoadMore = fetched.count == pageSize
        isLoading = false
        hasSearchedOnce = true
    }

    /// Triggered from each grid cell's `.onAppear` — once one of the last
    /// few items in the currently-loaded page scrolls into view, fetches
    /// the next page and appends it, giving the classic "infinite scroll"
    /// feel instead of the grid just dead-ending after the first 30 GIFs.
    private func loadMoreIfNeeded(currentItem: GifSearchResult) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        let thresholdIndex = results.index(results.endIndex, offsetBy: -6, limitedBy: results.startIndex) ?? results.startIndex
        guard let currentIndex = results.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex >= thresholdIndex
        else { return }
        Task { await loadNextPage() }
    }

    private func loadNextPage() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = searchGeneration
        let offset = currentOffset
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let fetched = trimmed.isEmpty
            ? await GifSearchService.trending(limit: pageSize, offset: offset)
            : await GifSearchService.search(query: trimmed, limit: pageSize, offset: offset)
        // A new search started while this page was in flight — its own
        // `runSearch()` already reset `results`/`currentOffset` for the new
        // query, so appending this now-stale page would splice unrelated
        // GIFs onto the wrong result set.
        guard generation == searchGeneration else { return }
        results.append(contentsOf: fetched)
        currentOffset += fetched.count
        canLoadMore = fetched.count == pageSize
    }

    private func pick(_ result: GifSearchResult) {
        guard !isDownloading else { return }
        isDownloading = true
        Task {
            defer { isDownloading = false }
            if let data = await GifSearchService.downloadData(for: result) {
                pendingCrop = PendingCrop(data: data)
            }
        }
    }
}

// MARK: - AnimatedGifPreviewCell

/// A grid preview cell that actually plays its GIF — downloads the preview
/// rendition, decodes it off the main thread, and caches the decoded result
/// by URL so scrolling the grid (which recreates cells via `LazyVGrid`/List
/// recycling) doesn't re-download-and-redecode a GIF it already showed this
/// session. Deliberately fetches only the *preview* URL (a small, GIPHY-
/// picked-small rendition), not the full-resolution one, to keep decoding
/// dozens of simultaneously-visible cells reasonable.
private struct AnimatedGifPreviewCell: View {
    let urlString: String?

    @State private var image: UIImage? = nil
    @State private var failed = false

    @MainActor
    private static var cache: [String: UIImage] = [:]

    var body: some View {
        Group {
            if let image {
                AnimatedImageView(image: image, contentMode: .scaleAspectFill)
            } else if failed {
                Rectangle().fill(AppTheme.surface).overlay(
                    Image(systemName: "photo").foregroundStyle(AppTheme.textSecondary)
                )
            } else {
                Rectangle().fill(AppTheme.surface).overlay(ProgressView())
            }
        }
        .task(id: urlString) {
            guard let urlString else { failed = true; return }
            if let cached = Self.cache[urlString] {
                image = cached
                return
            }
            guard let url = URL(string: urlString),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else {
                failed = true
                return
            }
            let decoded = isGIFData(data) ? await UIImage.gifImageAsync(data: data) : UIImage(data: data)
            guard let decoded else {
                failed = true
                return
            }
            Self.cache[urlString] = decoded
            image = decoded
        }
    }
}
