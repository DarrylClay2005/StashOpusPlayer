import SwiftUI

// MARK: - GalleryBackgroundView

struct GalleryBackgroundView: View {
    @EnvironmentObject var bg: BackgroundService

    @State private var displayedImage: UIImage? = nil
    @State private var animationID = UUID()

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if bg.isEnabled, !bg.images.isEmpty, let img = displayedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: bg.isBlurred ? 12 : 0, opaque: true)
                    .opacity(bg.opacity)
                    .id(animationID)
                    .transition(transitionForAnimation(bg.animation))
                    .animation(.easeInOut(duration: 0.6), value: animationID)
            }
        }
        .onChange(of: bg.currentIndex) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                animationID = UUID()
                if !bg.images.isEmpty {
                    displayedImage = bg.images[bg.currentIndex % bg.images.count]
                }
            }
        }
        .onAppear {
            if bg.isEnabled, !bg.images.isEmpty {
                displayedImage = bg.images[bg.currentIndex % bg.images.count]
            }
        }
    }

    // MARK: - Transition Factory

    func transitionForAnimation(_ anim: BackgroundAnimation) -> AnyTransition {
        switch anim {
        case .fade:
            return .opacity
        case .slideLeft:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .slideUp:
            return .asymmetric(
                insertion: .move(edge: .bottom),
                removal: .move(edge: .top)
            )
        case .zoomIn:
            return .scale(scale: 0.8).combined(with: .opacity)
        case .zoomOut:
            return .scale(scale: 1.2).combined(with: .opacity)
        case .flip:
            return .asymmetric(
                insertion: .scale(scale: 0.01, anchor: .center).combined(with: .opacity),
                removal: .scale(scale: 0.01, anchor: .center).combined(with: .opacity)
            )
        case .blur:
            return .opacity
        case .none:
            return .identity
        }
    }
}
