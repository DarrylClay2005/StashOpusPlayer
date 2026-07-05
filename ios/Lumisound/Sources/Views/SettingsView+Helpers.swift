import SwiftUI

extension SettingsView {

    // MARK: — Helpers

    func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    var mediaAccessStatusText: String {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:    return "Allowed"
        case .denied:        return "Denied"
        case .restricted:    return "Restricted"
        case .notDetermined: return "Not Asked"
        @unknown default:    return "Unknown"
        }
    }

    var mediaAccessStatusColor: Color {
        MPMediaLibrary.authorizationStatus() == .authorized
            ? AppTheme.success
            : AppTheme.warning
    }

    func pitchLabel(_ semitones: Float) -> String {
        if semitones == 0 { return "0 st" }
        let sign = semitones > 0 ? "+" : ""
        return String(format: "%@%.1f st", sign, semitones)
    }
}
