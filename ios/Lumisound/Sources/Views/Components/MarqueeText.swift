import SwiftUI

/// A single-line text view that automatically scrolls horizontally when the
/// text is wider than the space available, and behaves like a normal
/// (non-scrolling) `Text` otherwise. Used for long track titles/artist names
/// in prominent, fixed-width spots (mini-player, Now Playing) where
/// truncating with an ellipsis would hide useful information.
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary

    /// Horizontal gap between the looping copies of the text.
    private let gap: CGFloat = 32
    /// Scroll speed in points per second.
    private let speed: CGFloat = 28
    /// Pause before each scroll cycle begins.
    private let initialDelay: Double = 1.5

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width && containerWidth > 0

            Group {
                if needsScroll {
                    HStack(spacing: gap) {
                        Text(text).fixedSize()
                        Text(text).fixedSize()
                    }
                    .offset(x: animate ? -(textWidth + gap) : 0)
                    .animation(
                        animate
                            ? .linear(duration: Double((textWidth + gap) / speed)).repeatForever(autoreverses: false)
                            : nil,
                        value: animate
                    )
                } else {
                    Text(text)
                }
            }
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: containerWidth, alignment: .leading)
            .onAppear {
                containerWidth = geo.size.width
                if needsScroll { scheduleStart() }
            }
            .onChange(of: geo.size.width) { newWidth in
                containerWidth = newWidth
            }
            .onChange(of: needsScroll) { scroll in
                animate = false
                if scroll { scheduleStart() }
            }
            .onChange(of: text) { _ in
                animate = false
                if needsScroll { scheduleStart() }
            }
        }
        // Hidden copy used purely to measure the text's natural width.
        .background(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .background(GeometryReader { textGeo in
                    Color.clear
                        .onAppear { textWidth = textGeo.size.width }
                        .onChange(of: text) { _ in textWidth = textGeo.size.width }
                })
        )
        .clipped()
    }

    private func scheduleStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            animate = true
        }
    }
}
