import Foundation
import UIKit

/// Static device/app identifiers attached to logs so issues can be
/// correlated to a specific tvOS version/app build — mirrors
/// ios/Lumisound/Sources/Services/DeviceInfo.swift's iOS equivalent.
enum TVDeviceInfo {
    /// Hardware identifier such as "AppleTV6,2". Falls back to
    /// `UIDevice.current.model` ("Apple TV") if `utsname` can't be read.
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

    /// e.g. "17.0"
    static let osVersion: String = UIDevice.current.systemVersion

    /// e.g. "1.4.19" — `CFBundleShortVersionString`.
    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    /// e.g. "AppleTV6,2, tvOS 17.0" — for human-readable log context.
    static let summary: String = "\(modelIdentifier), tvOS \(osVersion)"
}

// MARK: - JWT subject extraction (log tagging only, not security-relevant)

enum TVJWT {
    /// Best-effort decode of a JWT's `sub` claim, for tagging log entries
    /// with the acting user id. Not signature-verified — this is purely for
    /// telemetry attribution, never for authorization (the bridge already
    /// verifies the token on every authenticated request).
    static func subject(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        // JWTs use base64url (no padding, `-`/`_` instead of `+`/`/`) —
        // convert to standard base64 before decoding.
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["sub"] as? String
    }
}
