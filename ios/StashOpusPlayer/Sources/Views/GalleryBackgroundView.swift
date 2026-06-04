import SwiftUI
import UIKit

// MARK: - GalleryBackgroundView

struct GalleryBackgroundView: View {
    @EnvironmentObject var bg: BackgroundService

    @State private var displayedImage: UIImage? = nil
    @State private var animationID = UUID()

    var body: some View {
        // GeometryReader gives an exact screen-sized canvas so scaledToFill can't
        // push outside the ZStack and stretch the parent layout.
        GeometryReader { geo in
            ZStack {
                AppTheme.background

                if bg.isEnabled, !bg.images.isEmpty, let img = displayedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        // Explicit frame prevents the image spilling outside layout bounds
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: bg.isBlurred ? 16 : 0, opaque: true)
                        .opacity(bg.opacity)
                        .id(animationID)
                        .transition(transitionForAnimation(bg.animation))
                        .animation(.easeInOut(duration: 0.6), value: animationID)
                }
            }
        }
        .ignoresSafeArea()
        // Index changed (shuffle timer fired)
        .onChange(of: bg.currentIndex) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                animationID = UUID()
                if !bg.images.isEmpty {
                    displayedImage = bg.images[bg.currentIndex % bg.images.count]
                }
            }
        }
        // Images array changed — fires when loadImagesFromDisk() finishes populating
        // the array after app launch. Without this handler, displayedImage stays nil
        // forever because onAppear fires before disk images are loaded.
        .onChange(of: bg.images) { newImages in
            guard bg.isEnabled, !newImages.isEmpty, displayedImage == nil else { return }
            displayedImage = newImages[bg.currentIndex % newImages.count]
        }
        // Toggle turned on mid-session
        .onChange(of: bg.isEnabled) { enabled in
            guard enabled, !bg.images.isEmpty else { return }
            displayedImage = bg.images[bg.currentIndex % bg.images.count]
        }
        .onAppear {
            guard bg.isEnabled, !bg.images.isEmpty else { return }
            displayedImage = bg.images[bg.currentIndex % bg.images.count]
        }
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
        case .blur:  return .opacity
        case .none:  return .identity
        }
    }
}
