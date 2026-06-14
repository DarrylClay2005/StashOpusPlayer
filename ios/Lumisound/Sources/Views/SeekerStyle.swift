import SwiftUI

enum SeekerStyle: String, CaseIterable, Identifiable {
    case waveform
    case classic
    case ring
    case bars
    case digital
    case pill
    case neonLine
    case dotTrack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waveform: return "Waveform"
        case .classic:  return "Classic"
        case .ring:     return "Ring"
        case .bars:     return "Bars"
        case .digital:  return "Digital"
        case .pill:     return "Pill"
        case .neonLine: return "Neon Line"
        case .dotTrack: return "Dot Track"
        }
    }

    var iconName: String {
        switch self {
        case .waveform: return "waveform"
        case .classic:  return "slider.horizontal.below.rectangle"
        case .ring:     return "circle.circle"
        case .bars:     return "chart.bar.xaxis"
        case .digital:  return "timer"
        case .pill:     return "rectangle.fill"
        case .neonLine: return "bolt.horizontal"
        case .dotTrack: return "circle.grid.3x3.fill"
        }
    }
}
