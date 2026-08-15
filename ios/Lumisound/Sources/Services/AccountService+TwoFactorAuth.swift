import Foundation

extension AccountService {

    // MARK: - Two-Factor Authentication (TOTP)
    //
    // Account -> Security's enable/disable flow for the bridge's TOTP 2FA
    // (auth.py's /auth/2fa/* endpoints, which predate this file — this is
    // just the client wiring for a backend feature that previously had no
    // app UI at all, so no account could actually turn it on). The
    // login-time counterpart (a code prompt when /auth/login responds
    // `requires_2fa`) lives in AccountService+PublicAPI.swift's
    // `completeTOTPLogin`/`pendingTOTPToken`.

    struct TOTPSetupResponse: Decodable {
        let secret: String
        let otpauth_url: String
    }

    /// Refreshes `isTOTPEnabled` from the server — call when Account ->
    /// Security appears, and after login, since the login response itself
    /// doesn't carry this flag (see /auth/2fa/status's doc comment).
    func refreshTOTPStatus() async {
        guard isLoggedIn else { return }
        struct Response: Decodable { let enabled: Bool }
        do {
            let data = try await makeRequest("/auth/2fa/status")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            isTOTPEnabled = decoded.enabled
        } catch {
            appWarn("refreshTOTPStatus failed: \(error.localizedDescription)", category: "account")
        }
    }

    /// Starts (or restarts) 2FA setup — generates a new secret server-side
    /// and returns it plus an `otpauth://` URI to render as a QR code.
    /// Does NOT enable 2FA yet; call `verifyTOTPSetup(code:)` with a code
    /// from the authenticator app to actually turn it on.
    func startTOTPSetup() async -> TOTPSetupResponse? {
        guard isLoggedIn else { return nil }
        errorMessage = nil
        do {
            let data = try await makeRequest("/auth/2fa/setup", method: "POST")
            return try JSONDecoder().decode(TOTPSetupResponse.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func verifyTOTPSetup(code: String) async -> Bool {
        guard isLoggedIn else { return false }
        errorMessage = nil
        struct Body: Encodable { let code: String }
        do {
            _ = try await makeRequest("/auth/2fa/verify", method: "POST", body: Body(code: code))
            isTOTPEnabled = true
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Requires the account password again — a stolen/left-open session
    /// alone shouldn't be enough to strip an account's second factor (same
    /// reasoning as the bridge's /auth/2fa/disable doc comment).
    @discardableResult
    func disableTOTP(password: String) async -> Bool {
        guard isLoggedIn else { return false }
        errorMessage = nil
        struct Body: Encodable { let password: String }
        do {
            _ = try await makeRequest("/auth/2fa/disable", method: "POST", body: Body(password: password))
            isTOTPEnabled = false
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
