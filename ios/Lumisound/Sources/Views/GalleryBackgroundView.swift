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
                    // Driving the swap through a single-element ForEach (rather
                    // than a bare `.id()` on one conditional Image) is what makes
                    // the crossfade actually overlap: ForEach tracks the leaving
                    // image (index N) and the entering image (index N+1) as two
                    // distinct elements, so the outgoing view runs its *removal*
                    // transition on top of the incoming one instead of being
                    // yanked instantly — which is why every animation previously
                    // blanked to the background before the next image faded in.
                    ZStack {
                        ForEach([bg.currentIndex], id: \.self) { index in
                            Image(uiImage: bg.images[index % bg.images.count])
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: bg.blurRadius, opaque: true)
                                .opacity(bg.opacity)
                                .transition(transitionForAnimation(bg.animation))
                        }
                    }
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
        case .slideRight: return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        case .slideUp:   return .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        case .slideDown: return .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom))
        case .zoomIn:    return .scale(scale: 0.8).combined(with: .opacity)
        case .zoomOut:   return .scale(scale: 1.2).combined(with: .opacity)
        // Zoom Blur — the incoming image rushes in from larger-than-screen while
        // sharpening from a blur.
        case .zoomBlur:  return .scale(scale: 1.4)
            .combined(with: .modifier(active: BlurTransitionModifier(radius: 24),
                                      identity: BlurTransitionModifier(radius: 0)))
            .combined(with: .opacity)
        case .flip:      return .asymmetric(
            insertion: .scale(scale: 0.01, anchor: .center).combined(with: .opacity),
            removal:   .scale(scale: 0.01, anchor: .center).combined(with: .opacity)
        )
        // Twist — images rotate + scale as they swap.
        case .twist:     return .asymmetric(
            insertion: .modifier(active: TwistTransitionModifier(angle: -25, scale: 0.7),
                                 identity: TwistTransitionModifier(angle: 0, scale: 1)).combined(with: .opacity),
            removal:   .modifier(active: TwistTransitionModifier(angle: 25, scale: 0.7),
                                 identity: TwistTransitionModifier(angle: 0, scale: 1)).combined(with: .opacity)
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

// MARK: - Twist Transition Modifier

/// Interpolates rotation + scale together for the "Twist" transition.
private struct TwistTransitionModifier: ViewModifier, Animatable {
    var angle: CGFloat
    var scale: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(angle, scale) }
        set { angle = newValue.first; scale = newValue.second }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(angle)))
            .scaleEffect(scale)
    }
}
