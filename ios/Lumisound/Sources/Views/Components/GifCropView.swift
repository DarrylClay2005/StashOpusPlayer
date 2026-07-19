import SwiftUI

// MARK: - GifCropView
//
// Lets a user reposition/zoom a picked GIF before it becomes their
// avatar/banner, rather than always getting whatever `.scaleAspectFill`'s
// automatic center-crop happens to keep — most GIFs are landscape, so an
// un-adjustable center-crop into a circular avatar or a wide banner
// routinely cuts off the actual subject. The crop *window* stays fixed in
// the middle of the screen; the image itself pans/zooms underneath it via
// drag/pinch, which is the same interaction model Twitter/Instagram-style
// avatar croppers use — simpler to reason about than a movable crop frame
// over a fixed image, since the math only has one moving part.
struct GifCropView: View {
    /// Raw GIF bytes as downloaded — cropping re-encodes from this, so the
    /// final result stays a real, independently-looping GIF.
    let sourceData: Data
    /// Width ÷ height of the crop window — 1.0 for an avatar, something
    /// wide (e.g. ~2.8) for a banner.
    let cropAspect: CGFloat
    /// Circular guide (avatar) vs. rounded-rectangle guide (banner). Purely
    /// cosmetic — the actual exported crop is always a plain rectangle
    /// either way, since a circular *file* isn't a thing; the app's own
    /// `.clipShape(Circle())` at display time handles the round mask.
    let isCircularGuide: Bool
    /// Cropped GIF bytes, ready to hand to `uploadAvatarData`/`uploadBannerData`.
    let onCropped: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage? = nil
    @State private var isProcessing = false
    @State private var scale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cropSize = cropWindowSize(in: geo.size)
                ZStack {
                    Color.black.ignoresSafeArea()

                    if let image {
                        AnimatedImageView(image: image, contentMode: .scaleAspectFit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale * gestureScale)
                            .offset(
                                x: offset.width + gestureOffset.width,
                                y: offset.height + gestureOffset.height
                            )
                            .gesture(
                                SimultaneousGesture(
                                    DragGesture()
                                        .updating($gestureOffset) { value, state, _ in
                                            state = value.translation
                                        }
                                        .onEnded { value in
                                            offset.width += value.translation.width
                                            offset.height += value.translation.height
                                        },
                                    MagnificationGesture()
                                        .updating($gestureScale) { value, state, _ in
                                            state = value
                                        }
                                        .onEnded { value in
                                            scale = max(1, scale * value)
                                        }
                                )
                            )
                    } else {
                        ProgressView().tint(.white)
                    }

                    CropGuideOverlay(cropSize: cropSize, isCircular: isCircularGuide)
                        .allowsHitTesting(false)
                }
                .clipped()
                .overlay {
                    if isProcessing {
                        ZStack {
                            Color.black.opacity(0.45)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .task {
                    image = await UIImage.gifImageAsync(data: sourceData)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use This") { applyCrop(in: geo.size, cropSize: cropSize) }
                            .disabled(image == nil || isProcessing)
                            .bold()
                    }
                }
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }

    private func cropWindowSize(in containerSize: CGSize) -> CGSize {
        let maxWidth = containerSize.width - 32
        if cropAspect >= 1 {
            let width = maxWidth
            let height = width / cropAspect
            return CGSize(width: width, height: height)
        } else {
            let height = min(maxWidth / cropAspect, containerSize.height - 160)
            return CGSize(width: height * cropAspect, height: height)
        }
    }

    /// Maps the crop window's on-screen rect back into the *source image's*
    /// own pixel coordinate space, given however the user has currently
    /// panned/zoomed it, then crops+re-encodes exactly that rect.
    private func applyCrop(in containerSize: CGSize, cropSize: CGSize) {
        guard let image, !isProcessing else { return }
        isProcessing = true

        // aspectFit base scale: the image is shown at this scale before the
        // user's own additional `scale` is layered on top.
        let baseScale = min(containerSize.width / image.size.width, containerSize.height / image.size.height)
        let effectiveScale = baseScale * scale
        let renderedSize = CGSize(width: image.size.width * effectiveScale, height: image.size.height * effectiveScale)
        let renderedOrigin = CGPoint(
            x: containerSize.width / 2 - renderedSize.width / 2 + offset.width,
            y: containerSize.height / 2 - renderedSize.height / 2 + offset.height
        )
        let cropWindowOrigin = CGPoint(
            x: containerSize.width / 2 - cropSize.width / 2,
            y: containerSize.height / 2 - cropSize.height / 2
        )

        // Crop window's origin/size relative to the rendered image, then
        // converted from view points back to the source image's own pixel
        // units (every UIImage this app decodes from raw GIF bytes has
        // scale == 1.0, so points and CGImage pixels are the same here).
        var cropRect = CGRect(
            x: (cropWindowOrigin.x - renderedOrigin.x) / effectiveScale,
            y: (cropWindowOrigin.y - renderedOrigin.y) / effectiveScale,
            width: cropSize.width / effectiveScale,
            height: cropSize.height / effectiveScale
        )
        // Clamp to the source image's actual bounds — panning/zooming can
        // otherwise propose a rect that hangs outside it.
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: image.size))
        guard cropRect.width > 1, cropRect.height > 1 else {
            isProcessing = false
            return
        }

        Task {
            defer { isProcessing = false }
            if let cropped = await UIImage.croppedGifData(from: sourceData, cropRect: cropRect) {
                onCropped(cropped)
                dismiss()
            }
        }
    }
}

// MARK: - CropGuideOverlay

/// Dims everything outside the crop window and outlines it — circular for
/// an avatar, rounded-rectangle for a banner. The dimming layer is a single
/// shape (the full-screen rect plus the crop cutout) filled with the
/// even-odd rule, which is the reliable way to punch a "hole" in SwiftUI —
/// blend-mode-based masking is finicky to get rendering correctly here.
private struct CropGuideOverlay: View {
    let cropSize: CGSize
    let isCircular: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DimmedHoleShape(cropSize: cropSize, isCircular: isCircular)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                strokedGuide
                    .frame(width: cropSize.width, height: cropSize.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // `.stroke(...)` is a `Shape`-only method — it has to be applied to the
    // concrete `Circle`/`RoundedRectangle` *before* the `if`/`else` branches
    // erase to `some View`, not after (that's a real compile error: "some
    // View has no member 'stroke'"), hence doing it per-branch here instead
    // of on a separately-erased `guideShape` property.
    @ViewBuilder
    private var strokedGuide: some View {
        if isCircular {
            Circle().stroke(.white, lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white, lineWidth: 2)
        }
    }
}

/// Full-rect path with a centered cutout (ellipse or rounded-rect) removed
/// via the even-odd fill rule.
private struct DimmedHoleShape: Shape {
    let cropSize: CGSize
    let isCircular: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = CGRect(
            x: rect.midX - cropSize.width / 2,
            y: rect.midY - cropSize.height / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        if isCircular {
            path.addEllipse(in: hole)
        } else {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 20, height: 20))
        }
        return path
    }
}
