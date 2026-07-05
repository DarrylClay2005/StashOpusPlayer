import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - DOB

    /// Set date of birth (ISO YYYY-MM-DD). Server enforces immutability once set.
    func setDateOfBirth(_ dob: String) async {
        guard isLoggedIn else { return }
        appLog("setDateOfBirth: setting DOB", category: "account")
        errorMessage = nil
        struct Body: Encodable { let date_of_birth: String }
        do {
            _ = try await makeRequest("/auth/me", method: "PUT", body: Body(date_of_birth: dob))
            hasDateOfBirth = true
            appLog("setDateOfBirth: success", category: "account")
        } catch let err as AccountError {
            appError("setDateOfBirth failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("setDateOfBirth error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }
}
