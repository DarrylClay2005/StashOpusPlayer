import Foundation

extension AccountService {

    // MARK: - Admin Dashboard
    //
    // Server-side (main.py's check_admin_or_operator) accepts either the
    // standalone ADMIN_TOKEN secret (the web dashboard's path) or a normal
    // user JWT belonging to the hardcoded operator account (this path) — no
    // separate credential is embedded in the app at all, so these calls go
    // through the exact same `makeRequest`/token every other account
    // endpoint uses. If the logged-in user isn't the operator account, the
    // server 401s exactly like any other endpoint would.

    /// Fetches the admin overview (users, storage, disk, job/error counts,
    /// concurrency). Powers `AdminDashboardView`.
    func fetchAdminOverview() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/admin/api/overview")
            adminOverview = try JSONDecoder().decode(AdminOverview.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchAdminDownloadJobs(limit: Int = 50) async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/admin/api/download-jobs?limit=\(limit)")
            adminDownloadJobs = try JSONDecoder().decode([AdminDownloadJob].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchAdminErrors(limit: Int = 50) async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/admin/api/errors?limit=\(limit)")
            adminErrors = try JSONDecoder().decode([AdminErrorLogEntry].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
