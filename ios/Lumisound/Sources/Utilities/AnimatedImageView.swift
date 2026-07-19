import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Animated GIF decoding

extension UIImage {
    /// Decodes GIF `data` into a single multi-frame `UIImage` (via
    /// `UIImage.animatedImage(with:duration:)`) that `UIImageView` animates
    /// automatically when assigned to its `.image` property — unlike
    /// `UIImage(data:)`, which only ever decodes a GIF's first frame. Returns
    /// `nil` if `data` isn't decodable as an image sequence at all.
    ///
    /// - Parameter maxDimension: when non-nil, every frame is decoded via
    ///   ImageIO's thumbnail path capped to this many pixels on its long edge
    ///   (same idea as `ImageDownsampler`, just per-frame) instead of being
    ///   decoded at full source resolution. A multi-frame `UIImage` holds
    ///   every one of its frames fully decoded in memory simultaneously for
    ///   as long as it's kept around and *continues paying full-resolution
    ///   blur/composite cost on every frame while animating* — for a gallery
    ///   that retains dozens of these at once (e.g. `BackgroundService`'s
    ///   326-image library), leaving this `nil` for a real photo-library GIF
    ///   is what caused main-thread saturation from `.blur()`-ing an
    ///   animating multi-hundred-MB image and made the whole Gallery
    ///   Background screen appear to render as an empty blank space below
    ///   the status row. `nil` (full resolution) is still the right default
    ///   for one-off, already-small assets (e.g. avatar/banner GIFs).
    static func gifImage(data: Data, maxDimension: CGFloat? = nil) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            // A single-frame "GIF" (some export tools produce these) — a
            // plain static UIImage is both correct and cheaper.
            return UIImage(data: data)
        }

        let thumbOpts: [CFString: Any]? = maxDimension.map { cap in
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: cap,
            ]
        }

        var frames: [UIImage] = []
        var totalDuration: Double = 0
        for index in 0..<count {
            let cgImage: CGImage? = thumbOpts != nil
                ? CGImageSourceCreateThumbnailAtIndex(source, index, thumbOpts as CFDictionary?)
                : CGImageSourceCreateImageAtIndex(source, index, nil)
            guard let cgImage else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += Self.gifFrameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: totalDuration > 0 ? totalDuration : Double(frames.count) * 0.1)
    }

    /// Off-main-thread wrapper around `gifImage(data:)` — decoding isn't
    /// free: it decompresses *every* frame into its own full-resolution
    /// `UIImage` up front, so a real-world GIF (a multi-hundred-KB/few-MB
    /// download with dozens of frames, e.g. from a GIF-search picker rather
    /// than a small hand-picked test file) can take long enough to visibly
    /// stall the UI when called directly from a `@MainActor`-isolated
    /// context — which is exactly how every call site in this codebase
    /// (AccountService, SocialService) invokes it today. Prefer this over
    /// the sync version anywhere the data didn't come from a tiny/trusted
    /// local source.
    static func gifImageAsync(data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            gifImage(data: data)
        }.value
    }

    /// One decoded GIF frame, kept as a raw `CGImage` (not yet wrapped in a
    /// `UIImage`) plus its own display duration — the intermediate form
    /// `croppedGifData(from:cropRect:)` needs, since re-encoding requires
    /// per-frame pixel data, not the single composed animated `UIImage`
    /// `gifImage(data:)` produces.
    struct GifFrame {
        let cgImage: CGImage
        let duration: Double
    }

    /// Decodes every frame of GIF `data` individually, preserving each
    /// frame's own delay — used by `croppedGifData(from:cropRect:)` to crop
    /// and re-encode. Unlike `gifImage(data:)`, this doesn't compose the
    /// frames into a single `UIImage` and doesn't fall back to treating a
    /// single-frame file as "just a static image" — callers that need to
    /// re-export always want the raw frame sequence, even a sequence of one.
    static func decodeGifFrames(data: Data) -> [GifFrame]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var frames: [GifFrame] = []
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(GifFrame(cgImage: cgImage, duration: gifFrameDuration(source: source, index: index)))
        }
        return frames.isEmpty ? nil : frames
    }

    /// Crops every frame of GIF `data` to `cropRect` (in the *source* image's
    /// own pixel coordinate space — i.e. `CGImage`-native units, which for
    /// every `UIImage` this app decodes from raw GIF bytes are the same as
    /// `UIImage.size` points, since none of them carry a non-1.0 `scale`) and
    /// re-encodes as a new, independently loopable GIF. Used by
    /// `GifCropView` so a user can reposition/zoom a picked GIF before it
    /// becomes their avatar/banner, rather than always getting whatever
    /// `.scaleAspectFill`'s automatic center-crop happens to keep.
    static func croppedGifData(from data: Data, cropRect: CGRect) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let frames = decodeGifFrames(data: data) else { return nil }
            let destData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                destData, UTType.gif.identifier as CFString, frames.count, nil
            ) else { return nil }

            let fileProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
            ]
            CGImageDestinationSetProperties(destination, fileProps as CFDictionary)

            for frame in frames {
                guard let cropped = frame.cgImage.cropping(to: cropRect) else { continue }
                let frameProps: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frame.duration]
                ]
                CGImageDestinationAddImage(destination, cropped, frameProps as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { return nil }
            return destData as Data
        }.value
    }

    private static func gifFrameDuration(source: CGImageSource, index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let duration = unclamped ?? clamped ?? 0.1
        // Guards against malformed GIFs with a near-zero delay, which browsers
        // (and this player) treat as "use a sane default" rather than a flicker.
        return duration < 0.02 ? 0.1 : duration
    }
}

/// Sniffs raw file data for a GIF header — used at pick-time to decide whether
/// to route through `UIImage.gifImage(data:)` (preserving animation) instead
/// of the app's usual downsample-to-static-JPEG pipeline.
func isGIFData(_ data: Data) -> Bool {
    guard data.count >= 6 else { return false }
    let header = data.prefix(6)
    return header.starts(with: Array("GIF87a".utf8)) || header.starts(with: Array("GIF89a".utf8))
}

// MARK: - AnimatedImageView

/// `UIViewRepresentable` wrapper around `UIImageView`, used anywhere the app
/// needs to actually PLAY an animated `UIImage` (produced by
/// `UIImage.gifImage(data:)`) — SwiftUI's own `Image(uiImage:)` never animates
/// a multi-frame `UIImage`, it always renders a single (first) frame. Static
/// images work through this view too (a `UIImageView` displays them exactly
/// like a plain `Image` would), so call sites that display a mix of static and
/// animated gallery entries can use this unconditionally rather than branching.
///
/// SwiftUI modifiers applied to this view from the outside (`.frame`,
/// `.clipped`, `.blur`, `.opacity`, `.scaleEffect`, `.transition`, etc.) all
/// keep working normally — they operate on the SwiftUI view tree regardless
/// of whether the leaf is an `Image` or a `UIViewRepresentable`.
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard uiView.image !== image else { return }
        uiView.image = image
        // Setting `.image` to a multi-frame `UIImage` (from
        // `animatedImage(with:duration:)`) is documented to auto-loop
        // without needing an explicit start — but that's the normal
        // storyboard/UIKit-native case. A `UIImageView` hosted through
        // `UIViewRepresentable` doesn't always get the same view-lifecycle
        // signals (e.g. `didMoveToWindow`) at the same time UIKit expects
        // them, which can leave the implicit auto-play never actually
        // kicking in. Calling this explicitly costs nothing when the image
        // is static (`.startAnimating()` on a single-frame `UIImage` is a
        // no-op) and removes any dependence on that timing working out.
        if image.images != nil {
            uiView.startAnimating()
        }
    }

    /// Without this, `UIViewRepresentable`'s default behavior lets SwiftUI
    /// query the wrapped `UIImageView`'s own `sizeThatFits`/intrinsic content
    /// size for layout purposes in some container contexts — notably inside
    /// `List`/`Form`, which use self-sizing table view cells that measure
    /// their content. A `UIImageView`'s intrinsic size is always based on its
    /// `.image`'s native pixel dimensions regardless of `contentMode`, so an
    /// avatar/banner picked from a real photo or a GIPHY GIF (often several
    /// hundred pixels per side) could blow a List row up to that size instead
    /// of respecting the `.frame(width:height:)` already applied at each call
    /// site — this is exactly what caused a giant near-empty area above the
    /// account row in Settings → Account once a user had a real (non-tiny)
    /// avatar image set.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        // IMPORTANT: `nil` here does NOT mean "no opinion, use the proposed
        // size" — it means the exact opposite: "size based on content",
        // i.e. defer to the UIImageView's own intrinsic size, identical to
        // not implementing this method at all. (Confirmed the hard way: an
        // earlier version of this file returned `nil` intending the former
        // and the giant-row bug it was meant to fix was still there.) To
        // actually honor whatever `.frame()` was applied on the SwiftUI
        // side, resolve and return the proposal itself.
        proposal.replacingUnspecifiedDimensions()
    }
}
