import Foundation
import UIKit

extension StreamingService {

    // MARK: - Public request builder

    /// Public wrapper so external services (e.g. BridgeHealthService) can build
    /// authenticated requests without duplicating URL construction logic.
    func makePublicRequest(_ path: String) -> URLRequest? {
        makeRequest(path)
    }
}
