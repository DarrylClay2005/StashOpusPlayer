import Foundation
import Network

/// A single always-on network-path observer — the only thing this app
/// needs from `NWPathMonitor` is "is the current path cellular-only", for
/// `downloadToLibrary`'s Wi-Fi Only Downloads guard to check. One shared
/// monitor rather than one per caller, since `NWPathMonitor` keeps its own
/// background dispatch queue running for as long as it's active.
final class NetworkPathMonitor {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.lumisound.networkpathmonitor")
    private let lock = NSLock()
    private var _isCellularOnly = false

    /// `true` when the current network path is up and using cellular
    /// without Wi-Fi also being available — the case Wi-Fi Only Downloads
    /// should block. `false` while the very first path update hasn't
    /// arrived yet, same as assuming a normal connection until told
    /// otherwise (fails open, not closed).
    var isCellularOnly: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCellularOnly
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let cellularOnly = path.status == .satisfied
                && path.usesInterfaceType(.cellular)
                && !path.usesInterfaceType(.wifi)
            self.lock.lock()
            self._isCellularOnly = cellularOnly
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
