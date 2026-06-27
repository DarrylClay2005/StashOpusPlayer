import Foundation

// MARK: - Auth models

struct TVUser: Codable, Hashable {
    let username: String?
    let display_name: String?
    var name: String { display_name ?? username ?? "You" }
}

private struct TVAuthResponse: Decodable {
    let token: String
    let user: TVUser?
}

// MARK: - TVAccount
//
// Minimal account service for tvOS: logs in against the bridge (/auth/login),
// persists the JWT, and exposes it for authenticated requests (per-user library).

@MainActor
final class TVAccount: ObservableObject {
    static let shared = TVAccount()

    @Published private(set) var token: String?
    @Published private(set) var user: TVUser?
    @Published var isLoggingIn = false
    @Published var errorText: String?

    var isLoggedIn: Bool { token != nil }

    private let baseURL = TVBridgeClient.shared.baseURL
    private let tokenKey = "tv.auth.token"
    private let userKey = "tv.auth.user"

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
        if let data = UserDefaults.standard.data(forKey: userKey) {
            user = try? JSONDecoder().decode(TVUser.self, from: data)
        }
    }

    func login(username: String, password: String) async {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !password.isEmpty else {
            errorText = "Enter your username and password."
            return
        }
        isLoggingIn = true
        errorText = nil
        defer { isLoggingIn = false }

        guard let url = URL(string: baseURL + "/auth/login") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let body = ["username": u, "password": password, "device_name": "Apple TV"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorText = "Login failed. Try again."
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                errorText = http.statusCode == 401
                    ? "Incorrect username or password."
                    : "Login failed (HTTP \(http.statusCode))."
                return
            }
            let decoded = try JSONDecoder().decode(TVAuthResponse.self, from: data)
            token = decoded.token
            user = decoded.user
            UserDefaults.standard.set(decoded.token, forKey: tokenKey)
            if let user = decoded.user, let enc = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(enc, forKey: userKey)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func logout() {
        token = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}
