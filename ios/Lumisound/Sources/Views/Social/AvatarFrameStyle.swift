import SwiftUI

// MARK: - Avatar frame styles
//
// Purely cosmetic, purely client-rendered decoration around a profile
// avatar — no image assets, no server-stored pixels, just SwiftUI strokes/
// gradients/animation layered outside the avatar's existing base ring (see
// ProfileHeaderCard). Validated server-side against this exact set
// (`_VALID_AVATAR_FRAMES` in main.py) so a malformed value can never reach
// the client; keep this list in sync if it ever changes.
enum AvatarFrameStyle: String, CaseIterable, Identifiable {
    case none, ring, glow, dashed, pulse, gradient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     return "None"
        case .ring:     return "Ring"
        case .glow:     return "Glow"
        case .dashed:   return "Dashed"
        case .pulse:    return "Pulse"
        case .gradient: return "Gradient"
        }
    }

    static func from(_ raw: String?) -> AvatarFrameStyle {
        AvatarFrameStyle(rawValue: raw ?? "none") ?? .none
    }
}

/// Renders the decorative frame around an avatar of the given `diameter`,
/// sized to sit just outside the avatar's own edge (and, for `.ring`'s base
/// stroke inside `ProfileHeaderCard`, outside that too). `mainTint`/`subTint`
/// are the profile's own accent colors — every style reuses them rather than
/// a fixed palette, so a frame always matches the rest of the profile.
struct AvatarFrameOverlay: View {
    let style: AvatarFrameStyle
    let diameter: CGFloat
    let mainTint: Color
    let subTint: Color

    @State private var isPulsing = false

    var body: some View {
        switch style {
        case .none:
            EmptyView()
        case .ring:
            Circle()
                .stroke(mainTint, lineWidth: 3)
                .frame(width: diameter + 10, height: diameter + 10)
        case .glow:
            Circle()
                .fill(mainTint.opacity(0.55))
                .frame(width: diameter + 6, height: diameter + 6)
                .blur(radius: 10)
        case .dashed:
            Circle()
                .stroke(mainTint, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                .frame(width: diameter + 12, height: diameter + 12)
        case .pulse:
            Circle()
                .stroke(mainTint, lineWidth: 2.5)
                .frame(width: diameter + 10, height: diameter + 10)
                .scaleEffect(isPulsing ? 1.18 : 1.0)
                .opacity(isPulsing ? 0 : 0.8)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: isPulsing)
                .onAppear { isPulsing = true }
        case .gradient:
            Circle()
                .stroke(
                    AngularGradient(colors: [mainTint, subTint, mainTint], center: .center),
                    lineWidth: 3.5
                )
                .frame(width: diameter + 10, height: diameter + 10)
        }
    }
}

/// A row of tappable frame-style previews, mirroring `AccentColorPickerView`
/// exactly — same picker shape, just previewing frame styles on a small
/// swatch avatar instead of a plain color circle.
struct AvatarFramePickerView: View {
    let mainTint: Color
    let subTint: Color
    @Binding var selected: AvatarFrameStyle

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AvatarFrameStyle.allCases) { style in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selected = style
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            AvatarFrameOverlay(style: style, diameter: 40, mainTint: mainTint, subTint: subTint)
                            Circle()
                                .fill(mainTint.opacity(0.25))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                        }
                        .frame(width: 54, height: 54)

                        Text(style.label)
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(selected == style ? mainTint : AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
