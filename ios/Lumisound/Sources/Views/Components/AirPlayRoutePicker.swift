import SwiftUI
import AVKit

/// AirPlay / audio-output route picker. There's no native SwiftUI control, so we
/// wrap UIKit's `AVRoutePickerView`. Tapping it presents the system route chooser
/// (AirPlay speakers, Bluetooth, etc.) and the glyph highlights when output is
/// routed somewhere other than the device.
struct AirPlayRoutePicker: UIViewRepresentable {
    var tint: UIColor
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = activeTint
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = activeTint
    }
}
