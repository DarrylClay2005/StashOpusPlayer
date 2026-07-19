import ImageIO
import SwiftUI
import UIKit

// MARK: - Animated GIF decoding

extension UIImage {
    /// Decodes GIF `data` into a single multi-frame `UIImage` (via
    /// `UIImage.animatedImage(with:duration:)`) that `UIImageView` animates
    /// automatically when assigned to its `.image` property — unlike
    /// `UIImage(data:)`, which only ever decodes a GIF's first frame. Returns
    /// `nil` if `data` isn't decodable as an image sequence at all.
    static func gifImage(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            // A single-frame "GIF" (some export tools produce these) — a
            // plain static UIImage is both correct and cheaper.
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        var totalDuration: Double = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
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
    /// avatar image set. Returning `nil` tells SwiftUI "no opinion, use your
    /// own proposed size" — i.e. respect the outer `.frame()` constraint.
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
