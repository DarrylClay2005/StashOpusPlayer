import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Public API

    func login(username: String, password: String, deviceName: String = UIDevice.current.name) async {
        appLog("Login attempt: \(username)", category: "account")
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let device_name: String
        }
        do {
            let data = try await makeRequest(
                "/auth/login",
                method: "POST",
                body: Body(username: username, password: password, device_name: deviceName)
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            appLog("Login success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Login failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Login error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func register(
        username: String,
        password: String,
        email: String?,
        displayName: String?
    ) async {
        appLog("Register attempt: \(username)", category: "account")
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let email: String?
            let display_name: String?
        }
        do {
            let data = try await makeRequest(
                "/auth/register",
                method: "POST",
                body: Body(
                    username: username,
                    password: password,
                    email: email.flatMap { $0.isEmpty ? nil : $0 },
                    display_name: displayName.flatMap { $0.isEmpty ? nil : $0 }
                )
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            appLog("Register success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Register failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Register error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        appLog("Logout: \(currentUser?.username ?? "?")", category: "account")
        errorMessage = nil
        if token != nil {
            _ = try? await makeRequest("/auth/logout", method: "POST", body: EmptyBody())
        }
        clearSession()
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/auth/me")
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("refreshMe: updated profile for \(user.username)", category: "account")
        } catch let err as AccountError where err.statusCode == 401 {
            appWarn("refreshMe: session expired, clearing", category: "account")
            clearSession()
        } catch {
            appWarn("refreshMe: \(error.localizedDescription) — using cached user", category: "account")
        }
    }

    /// Update the display name on the server and locally.
    func updateDisplayName(_ newName: String) async {
        guard isLoggedIn else { return }
        appLog("updateDisplayName: \"\(newName)\"", category: "account")
        errorMessage = nil
        struct Body: Encodable { let display_name: String }
        do {
            let data = try await makeRequest("/auth/me", method: "PUT", body: Body(display_name: newName))
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("updateDisplayName: success", category: "account")
        } catch let err as AccountError {
            appError("updateDisplayName failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("updateDisplayName error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }
}
