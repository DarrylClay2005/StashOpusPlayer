import Foundation

extension AccountService {

    // MARK: - Profile Bio (Feature: profile-bio)
    //
    // A short free-text tagline shown on the user's profile (AccountView),
    // alongside their display name — its own tiny table/endpoint on the
    // bridge (ios_user_profile_bio / GET+PUT /user/bio) rather than another
    // field crammed into the account model, so it doesn't need to touch the
    // existing (already fragile, positional-column) user-row/settings code.

    struct BioResponse: Decodable { let bio: String }

    func fetchBio() async -> String {
        guard isLoggedIn else { return "" }
        do {
            let data = try await makeRequest("/user/bio")
            return try JSONDecoder().decode(BioResponse.self, from: data).bio
        } catch {
            appWarn("fetchBio failed: \(error.localizedDescription)", category: "account")
            return ""
        }
    }

    @discardableResult
    func setBio(_ bio: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let bio: String }
        do {
            _ = try await makeRequest("/user/bio", method: "PUT", body: Body(bio: bio))
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
