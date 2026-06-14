import Foundation
import UIKit

/// Static device/app identifiers attached to logs and bug reports so issues can
/// be correlated to a specific hardware model and OS/app version — e.g. "only
/// reproduces on iPhone12,1 / iOS 16.x". `UIDevice.current.model` always returns
/// the generic "iPhone"/"iPad", so the hardware identifier (e.g. "iPhone15,2")
/// is read from `utsname` instead.
enum DeviceInfo {
    /// Hardware identifier such as "iPhone15,2" or "iPad13,4". Falls back to
    /// `UIDevice.current.model` if `utsname` can't be read (e.g. simulator quirks).
    static let modelIdentifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }()

    /// e.g. "16.4.1"
    static let osVersion: String = UIDevice.current.systemVersion

    /// e.g. "1.3.46" — `CFBundleShortVersionString`.
    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    /// e.g. "iPhone15,2, iOS 16.4.1" — used for bug reports and other
    /// human-readable summaries.
    static let summary: String = "\(modelIdentifier), iOS \(osVersion)"
}
