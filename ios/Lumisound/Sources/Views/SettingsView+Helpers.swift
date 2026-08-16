import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — Helpers

    func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    /// Redesigned section header — a small icon in a rounded, tinted badge
    /// next to the label, instead of plain uppercase text alone. Each
    /// section picks its own `tint`/`icon` so Settings' many sections read
    /// as visually distinct categories at a glance instead of one
    /// undifferentiated list — the core idea behind this screen's redesign.
    /// The plain-text `sectionHeader(_:)` above is kept for any call site
    /// that hasn't been moved to this one yet; both render at the same
    /// height so mixing them doesn't cause list-row jitter.
    func sectionHeader(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text.uppercased())
                .font(AppTheme.bodyFont(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .kerning(0.8)
        }
    }

    /// Settings redesign, part 2: each section's row background gets a very
    /// faint wash of that section's own `sectionHeader` tint (via
    /// `Color.mixed(with:amount:)`, the same blend helper Profile
    /// customization's decoration/effect overlays use) instead of every
    /// section sharing one flat `AppTheme.surface` — carries the "each
    /// category is visually its own color" idea from the header badges down
    /// into the row itself. The mix amount is deliberately small (6%) so it
    /// reads as a subtle color hint, not a colored card — this screen's
    /// `.listStyle(.plain)` was chosen specifically so sections stay a
    /// continuous surface rather than floating disconnected boxes (see
    /// `SettingsView.body`'s doc comment), and a strong per-section tint
    /// would fight that.
    func tintedRowBackground(_ tint: Color) -> Color {
        AppTheme.surface.mixed(with: tint, amount: 0.06)
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
