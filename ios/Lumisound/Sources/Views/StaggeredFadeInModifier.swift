import SwiftUI
import UniformTypeIdentifiers

// MARK: - StaggeredFadeInModifier

/// Fades each result row in with a small per-index delay whenever `token` changes.
struct StaggeredFadeInModifier: ViewModifier {
    let index: Int
    let token: UUID
    @State private var visible: Bool = false

    private var delay: Double { Double(min(index, 19)) * 0.04 }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                .easeOut(duration: 0.25).delay(delay),
                value: visible
            )
            .onAppear { visible = true }
            .onChange(of: token) { _ in
                visible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    visible = true
                }
            }
    }
}
