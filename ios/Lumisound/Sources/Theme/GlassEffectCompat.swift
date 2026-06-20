import SwiftUI

// MARK: - Liquid Glass compatibility helpers
//
// iOS 26 introduced the "Liquid Glass" material (`.glassEffect()` /
// `GlassEffectContainer`), which floating chrome (mini-player, toasts,
// FABs) should adopt for visual parity with system UI. Lumisound's
// deployment target is iOS 16, so every use is gated behind
// `#available(iOS 26, *)` with the existing `Material` look as the
// fallback on older OS versions.
//
// All variants overlay a user-customizable tint (see `GlassSettings`) clipped
// to the same shape, so the "Liquid Glass" Settings screen's tone/strength
// sliders affect every glass surface app-wide.

extension View {
    /// User-tint overlay applied on top of the base glass/material, clipped to
    /// `shape`. `.allowsHitTesting(false)` so it never intercepts taps on
    /// interactive glass (buttons/FABs).
    @ViewBuilder
    fileprivate func glassTintOverlay<S: Shape>(in shape: S) -> some View {
        let tint = GlassSettings.shared.tintColor
        if tint != .clear {
            self.overlay(shape.fill(tint).allowsHitTesting(false))
        } else {
            self
        }
    }

    /// Applies Liquid Glass on iOS 26+, falling back to the given
    /// `Material` (matching the look this call site used pre-iOS 26).
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, fallback: Material = .ultraThinMaterial) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape).glassTintOverlay(in: shape)
        } else {
            self.background(fallback, in: shape).glassTintOverlay(in: shape)
        }
    }

    /// Applies Liquid Glass on iOS 26+, falling back to an arbitrary
    /// `ShapeStyle` (e.g. a flat tint `Color`) rather than just a `Material`
    /// — for call sites (like song cards) whose pre-iOS 26 look used a solid
    /// tint instead of a translucent material.
    @ViewBuilder
    func adaptiveGlass<S: Shape, F: ShapeStyle>(in shape: S, fallback: F) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape).glassTintOverlay(in: shape)
        } else {
            self.background(fallback, in: shape).glassTintOverlay(in: shape)
        }
    }

    /// Applies a tinted, interactive Liquid Glass effect on iOS 26+ (for
    /// tappable floating controls), falling back to the given `Material`.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(tint: Color, in shape: S, fallback: Material = .ultraThinMaterial) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape).glassTintOverlay(in: shape)
        } else {
            self.background(fallback, in: shape).glassTintOverlay(in: shape)
        }
    }

    /// Tinted, interactive Liquid Glass on iOS 26+ (e.g. for a "now playing"
    /// highlighted card), falling back to an arbitrary `ShapeStyle`.
    @ViewBuilder
    func adaptiveGlass<S: Shape, F: ShapeStyle>(tint: Color, in shape: S, fallback: F) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape).glassTintOverlay(in: shape)
        } else {
            self.background(fallback, in: shape).glassTintOverlay(in: shape)
        }
    }
}
