import ImageIO
import UIKit

/// Shared, scale-safe image downsampling.
///
/// Every raster resize in the app must route through here. The core trap this
/// type exists to centralize: `UIGraphicsImageRenderer`'s default format
/// renders at the *device screen scale*, so an unformatted renderer sized in
/// "pixels" silently produces 2–3× the intended dimensions (the bug that once
/// wrote 3600×3600 artwork cache files on @3x phones). All helpers here work
/// in physical pixels and render at scale 1.
enum ImageDownsampler {

    /// Downsamples straight from an encoded image file — ImageIO decodes only
    /// the pixels needed for the thumbnail, never the full bitmap.
    static func downsampled(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, sourceOpts) else { return nil }
        return thumbnail(from: src, maxPixelSize: maxPixelSize)
    }

    /// Downsamples straight from encoded image data (same ImageIO path as
    /// `downsampled(at:)`, for callers that already hold the bytes).
    static func downsampled(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, sourceOpts) else { return nil }
        return thumbnail(from: src, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Scales an already-decoded image so its longest side is at most
    /// `maxPixelSize` physical pixels (`size × scale`, not points). Returns
    /// the input unchanged when it already fits.
    static func downscaled(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pw = image.size.width * image.scale
        let ph = image.size.height * image.scale
        guard pw > 0, ph > 0, pw > maxPixelSize || ph > maxPixelSize else { return image }
        let s = min(maxPixelSize / pw, maxPixelSize / ph)
        let target = CGSize(width: max(1, (pw * s).rounded()), height: max(1, (ph * s).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// `downscaled` + JPEG encode, for handoff payloads (widget App Group
    /// file, watch application context).
    static func jpegData(_ image: UIImage, maxPixelSize: CGFloat, compressionQuality: CGFloat) -> Data? {
        downscaled(image, maxPixelSize: maxPixelSize).jpegData(compressionQuality: compressionQuality)
    }
}
