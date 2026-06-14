import SwiftUI
import UIKit

/// A two-color palette sampled from a piece of artwork, used to drive the
/// ambient glow behind the Now Playing artwork display.
struct ArtworkPalette: Equatable {
    let primary: Color
    let secondary: Color
}

enum ArtworkColorExtractor {
    /// Downsamples `image` to a tiny bitmap and averages two halves (top-left
    /// vs. bottom-right) to produce a simple two-color palette. This is
    /// intentionally cheap — it runs on every track change — and avoids any
    /// heavyweight clustering for what's ultimately a soft background blur.
    static func palette(from image: UIImage) -> ArtworkPalette? {
        guard let cgImage = image.cgImage else { return nil }

        let side = 12
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        func averageColor(predicate: (Int, Int) -> Bool) -> Color {
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, count = 0.0
            for y in 0..<side {
                for x in 0..<side where predicate(x, y) {
                    let offset = (y * side + x) * bytesPerPixel
                    rSum += Double(pixels[offset])
                    gSum += Double(pixels[offset + 1])
                    bSum += Double(pixels[offset + 2])
                    count += 1
                }
            }
            guard count > 0 else { return AppTheme.dynamicAccent }
            return Color(red: rSum / count / 255, green: gSum / count / 255, blue: bSum / count / 255)
        }

        let primary = averageColor { x, y in x + y < side }
        let secondary = averageColor { x, y in x + y >= side }
        return ArtworkPalette(primary: primary, secondary: secondary)
    }
}
