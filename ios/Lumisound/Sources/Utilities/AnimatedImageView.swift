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
    }
}
