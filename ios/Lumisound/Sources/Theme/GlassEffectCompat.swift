import SwiftUI

// MARK: - Liquid Glass compatibility helpers
//
// iOS 26 introduced the "Liquid Glass" material (`.glassEffect()` /
// `GlassEffectContainer`), which floating chrome (mini-player, toasts,
// FABs) should adopt for visual parity with system UI. Lumisound's
// deployment target is iOS 16, so every use is gated behind
// `#available(iOS 26, *)` with the existing `Material` look as the
// fallback on older OS versions.

extension View {
    /// Applies Liquid Glass on iOS 26+, falling back to the given
    /// `Material` (matching the look this call site used pre-iOS 26).
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, fallback: Material = .ultraThinMaterial) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Applies a tinted, interactive Liquid Glass effect on iOS 26+ (for
    /// tappable floating controls), falling back to the given `Material`.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(tint: Color, in shape: S, fallback: Material = .ultraThinMaterial) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }
}
