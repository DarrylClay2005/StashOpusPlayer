import SwiftUI

struct ToastView: View {
    let text: String
    var icon: String = "checkmark.circle.fill"
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isError ? AppTheme.error : AppTheme.success)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    isError ? AppTheme.error.opacity(0.35) : AppTheme.success.opacity(0.35),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func toast(message: Binding<String?>, icon: String = "checkmark.circle.fill", isError: Bool = false) -> some View {
        self.overlay(alignment: .top) {
            if let text = message.wrappedValue {
                ToastView(text: text, icon: icon, isError: isError)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(9999)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            message.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message.wrappedValue)
    }
}
