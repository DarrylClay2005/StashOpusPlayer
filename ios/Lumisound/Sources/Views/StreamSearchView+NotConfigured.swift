import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Not configured

    var notConfiguredView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.warning.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "server.rack")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(AppTheme.warning)
            }

            VStack(spacing: 6) {
                Text("Streaming Unavailable")
                    .font(AppTheme.headlineFont(size: 18))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Streaming search is currently unavailable. Please try again later.")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            NavigationLink(destination: SettingsView()) {
                Label("Open Settings", systemImage: "gearshape")
                    .font(AppTheme.bodyFont(size: 14).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(AppTheme.dynamicAccentGradient, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
