import Foundation

/// Sends and receives Darwin (cross-process) notifications for Widget ↔ App communication.
/// Darwin notifications are delivered between processes via the kernel, making them suitable
/// for widget extension → main app playback control commands.
final class DarwinWidgetBridge {
    static let shared = DarwinWidgetBridge()

    static let togglePlayback = "com.lumisound.ios.widget.togglePlayback"
    static let skipNext       = "com.lumisound.ios.widget.skipNext"

    private var callbacks: [String: [() -> Void]] = [:]

    private init() {}

    /// Posts a Darwin notification visible to all processes on the device.
    static func post(name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    /// Registers `callback` to be invoked on the main thread when `name` is received.
    /// Safe to call multiple times; each call appends an additional callback.
    func addObserver(name: String, callback: @escaping () -> Void) {
        callbacks[name, default: []].append(callback)
        let nc = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            nc,
            Unmanaged.passUnretained(self).toOpaque(),
            Self.darwinCallback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static let darwinCallback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer, let name else { return }
        let bridge = Unmanaged<DarwinWidgetBridge>.fromOpaque(observer).takeUnretainedValue()
        let notifName = name.rawValue as String
        DispatchQueue.main.async {
            bridge.callbacks[notifName]?.forEach { $0() }
        }
    }
}
