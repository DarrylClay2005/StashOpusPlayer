import SwiftUI

// MARK: - TVDesignSystem
//
// Shared visual language for the tvOS port — "Aurora": a slowly drifting,
// softly colored ambient backdrop behind every screen (echoing the Now
// Playing screen's artwork-glow concept, but content-agnostic since most
// screens don't have a single piece of artwork to draw from), a consistent
// gradient placeholder for art that hasn't loaded (or never had any) instead
// of a flat gray box, and a shared section-header style with an accent
// glyph. One place to define the look so every screen reads as part of the
// same app instead of a loose collection of plain system-styled lists.

// MARK: Ambient background

/// Three soft, oversized blurred color fields drifting on independent slow
/// loops behind the content — subtle enough to stay out of the way of text
/// and focus outlines, present enough that the app doesn't read as flat
/// black everywhere. Intentionally cheap: three blurred circles, no images,
/// no per-frame work — this runs behind scrolling content on every screen.
struct TVAmbientBackground: View {
    var accent: Color = .accentColor
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black
            Circle()
                .fill(accent.opacity(0.35))
                .frame(width: 900, height: 900)
                .blur(radius: 220)
                .offset(x: drift ? -260 : -340, y: drift ? -260 : -180)
            Circle()
                .fill(Color.purple.opacity(0.28))
                .frame(width: 760, height: 760)
                .blur(radius: 200)
                .offset(x: drift ? 380 : 300, y: drift ? 120 : 220)
            Circle()
                .fill(Color.blue.opacity(0.22))
                .frame(width: 640, height: 640)
                .blur(radius: 180)
                .offset(x: drift ? -120 : -40, y: drift ? 340 : 420)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

extension View {
    /// Drops `TVAmbientBackground` behind this view — apply once, near the
    /// root of a screen's `body` (e.g. wrapping a `ScrollView`), not per row/
    /// card.
    func tvAmbientBackground(accent: Color = .accentColor) -> some View {
        background(TVAmbientBackground(accent: accent))
    }
}

// MARK: Art placeholder

/// Replaces the flat `Color.gray.opacity(0.3)` box every grid card used to
/// fall back to with a subtle accent-tinted gradient — still clearly a
/// placeholder (never mistaken for real artwork), but one that belongs to
/// this app's palette instead of a generic gray tile.
struct TVArtPlaceholder: View {
    let systemImage: String
    var iconScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.5), Color.black.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.system(size: 44 * iconScale, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: Section header

/// Shared header for the horizontally-scrolling sections on Discover (and
/// anywhere else that wants the same treatment) — a short accent-colored
/// rule next to the title is a small, cheap way to make section starts
/// visually distinct from the plain bold-text headers used before.
struct TVSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 34)
                Text(title).font(.system(size: 34, weight: .bold))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }
}

// MARK: Glass panel

/// A translucent, blurred panel background — used for stat tiles, form
/// panels, and other content that needs to sit legibly on top of
/// `TVAmbientBackground` without a hard-edged solid fill.
struct TVGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func tvGlassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(TVGlassPanel(cornerRadius: cornerRadius))
    }
}
