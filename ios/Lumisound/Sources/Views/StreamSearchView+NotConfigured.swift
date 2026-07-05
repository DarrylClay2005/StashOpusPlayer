import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Not configured

    var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Streaming Unavailable")
                .font(AppTheme.headlineFont(size: 18))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Streaming search is currently unavailable. Please try again later.")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NavigationLink(destination: SettingsView()) {
                Label("Open Settings", systemImage: "gearshape")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.dynamicAccent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
