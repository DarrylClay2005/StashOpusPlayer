import SwiftUI

enum SeekerStyle: String, CaseIterable, Identifiable {
    case waveform
    case classic
    case ring
    case bars

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waveform: return "Waveform"
        case .classic:  return "Classic"
        case .ring:     return "Ring"
        case .bars:     return "Bars"
        }
    }

    var iconName: String {
        switch self {
        case .waveform: return "waveform"
        case .classic:  return "slider.horizontal.below.rectangle"
        case .ring:     return "circle.circle"
        case .bars:     return "chart.bar.xaxis"
        }
    }
}
