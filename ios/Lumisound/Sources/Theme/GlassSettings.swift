import SwiftUI

// MARK: - GlassSettings
//
// User-customizable parameters for the app's Liquid Glass surfaces (song
// cards, mini-player, toasts, FABs…). `adaptiveGlass` (GlassEffectCompat.swift)
// reads these at render time to apply a tint overlay of the chosen tone and
// strength on top of the base glass/material, and to scale the fallback
// material's translucency. Persisted in UserDefaults so the look survives
// relaunches; the customization screen (GlassSettingsView) observes this for a
// live preview, and the rest of the app picks up changes on its next redraw.

@MainActor
final class GlassSettings: ObservableObject {
    static let shared = GlassSettings()

    private enum Keys {
        static let tintStrength = "glass_tintStrength"
        static let tintHue = "glass_tintHue"
        static let useAccentTint = "glass_useAccentTint"
        static let translucency = "glass_translucency"
    }

    /// 0…1 — how strongly the chosen tone is overlaid on the glass. 0 = pure
    /// clear glass, 1 = a strong wash of color.
    @Published var tintStrength: Double {
        didSet { UserDefaults.standard.set(tintStrength, forKey: Keys.tintStrength) }
    }
    /// 0…1 — hue of the custom tint (the "tone"). Ignored when `useAccentTint`
    /// is true (the app accent color is used instead).
    @Published var tintHue: Double {
        didSet { UserDefaults.standard.set(tintHue, forKey: Keys.tintHue) }
    }
    /// When true, glass is tinted with the app's dynamic accent color rather
    /// than the custom `tintHue`.
    @Published var useAccentTint: Bool {
        didSet { UserDefaults.standard.set(useAccentTint, forKey: Keys.useAccentTint) }
    }
    /// 0…1 — opacity of the pre-iOS-26 fallback material/colour, so users on
    /// older OSes can still tune how see-through the glass surfaces feel.
    @Published var translucency: Double {
        didSet { UserDefaults.standard.set(translucency, forKey: Keys.translucency) }
    }

    private init() {
        let d = UserDefaults.standard
        tintStrength = d.object(forKey: Keys.tintStrength) as? Double ?? 0.18
        tintHue = d.object(forKey: Keys.tintHue) as? Double ?? 0.58   // a soft blue default
        useAccentTint = d.object(forKey: Keys.useAccentTint) as? Bool ?? true
        translucency = d.object(forKey: Keys.translucency) as? Double ?? 1.0
    }

    /// The resolved tint color (accent or custom hue) at the configured
    /// strength, ready to overlay on a glass shape. Returns `.clear` when the
    /// strength is effectively zero so call sites can skip the overlay.
    var tintColor: Color {
        guard tintStrength > 0.001 else { return .clear }
        let base: Color = useAccentTint
            ? AppTheme.dynamicAccent
            : Color(hue: tintHue, saturation: 0.55, brightness: 0.92)
        // Cap the overlay so even max strength stays a tint, not an opaque fill.
        return base.opacity(tintStrength * 0.4)
    }

    func resetToDefaults() {
        tintStrength = 0.18
        tintHue = 0.58
        useAccentTint = true
        translucency = 1.0
    }
}
