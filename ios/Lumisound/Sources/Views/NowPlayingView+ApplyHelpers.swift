import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Apply Helpers

    func applySpeedInput() {
        if let parsed = Double(speedInput) {
            let clamped = Float(min(max(parsed, 0.1), 8.0))
            var settings = player.audioSettings
            settings.speed = clamped
            player.audioSettings = settings
        }
        editingSpeed = false
    }

    func applyPitchInput() {
        if let parsed = Double(pitchInput) {
            let clamped = Float(min(max(parsed, -24.0), 24.0))
            var settings = player.audioSettings
            settings.pitchSemitones = clamped
            player.audioSettings = settings
        }
        editingPitch = false
    }
}
