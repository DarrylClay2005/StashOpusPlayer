import SwiftUI
import UIKit

// MARK: - GalleryBackgroundView

struct GalleryBackgroundView: View {
    @EnvironmentObject var bg: BackgroundService

    var body: some View {
        // GeometryReader gives an exact screen-sized canvas so scaledToFill can't
        // push outside the ZStack and stretch the parent layout.
        GeometryReader { geo in
            ZStack {
                AppTheme.background

                // Read directly from the service — no intermediate @State needed.
                // currentIndex change drives the transition; the image is always
                // images[currentIndex % count] so the first image appears the
                // moment isEnabled + images are both true, without any onAppear
                // ordering dependency.
                if bg.isEnabled, !bg.images.isEmpty {
                    let img = bg.images[bg.currentIndex % bg.images.count]
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: bg.blurRadius, opaque: true)
                        .opacity(bg.opacity)
                        .id(bg.currentIndex)
                        .transition(transitionForAnimation(bg.animation))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Transition Factory

    func transitionForAnimation(_ anim: BackgroundAnimation) -> AnyTransition {
        switch anim {
        case .fade:      return .opacity
        case .slideLeft: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .slideUp:   return .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        case .zoomIn:    return .scale(scale: 0.8).combined(with: .opacity)
        case .zoomOut:   return .scale(scale: 1.2).combined(with: .opacity)
        case .flip:      return .asymmetric(
            insertion: .scale(scale: 0.01, anchor: .center).combined(with: .opacity),
            removal:   .scale(scale: 0.01, anchor: .center).combined(with: .opacity)
        )
        // "Blur In brings the next image into focus" (per the Help screen) — the
        // incoming image should visibly sharpen from a blur, not just crossfade
        // like .fade does. A bare .opacity here made "Blur In" indistinguishable
        // from "Fade", silently dropping the feature its own label promises.
        case .blur:  return .modifier(
            active:   BlurTransitionModifier(radius: 28),
            identity: BlurTransitionModifier(radius: 0)
        ).combined(with: .opacity)
        case .none:  return .identity
        }
    }
}

// MARK: - Blur Transition Modifier

/// Drives `.blur(radius:)` as an interpolated transition: the incoming image
/// sharpens from `radius` down to 0, the outgoing image blurs from 0 up to `radius`.
private struct BlurTransitionModifier: ViewModifier, Animatable {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
