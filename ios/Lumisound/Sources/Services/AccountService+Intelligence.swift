import Foundation

/// One AI-assisted metadata pick, as returned by `resolveMetadata`. Carries
/// `memoryID` so a later manual correction (see
/// `LibraryManager.applyMetadataCorrection`) can be reported back to Aria
/// Lumi via `reportMetadataCorrection`, closing the learning loop.
struct MetadataResolution {
    let bestIndex: Int
    let memoryID: Int?
}

extension AccountService {

    // MARK: - Aria Lumi: AI-Assisted Suggestions (opt-in; see ios-bridge/intelligence.py)

    /// Asks Aria Lumi (the bridge's AI-assisted metadata resolver) to pick
    /// the best candidate for an ambiguous local file (multiple
    /// similarly-named results, no exact title match). Returns `nil`
    /// whenever the feature is off, the user is logged out, the network
    /// call fails, or she has no confident pick — in every case the caller
    /// falls back to its existing exact-match-or-first-result heuristic
    /// unchanged.
    func resolveMetadata(filename: String, candidates: [MetadataCandidate]) async -> MetadataResolution? {
        guard isLoggedIn, currentUser?.aiAssistedSuggestions == true, !candidates.isEmpty else {
            return nil
        }
        struct Body: Encodable {
            let filename: String
            let candidates: [MetadataCandidate]
        }
        struct Response: Decodable {
            let best_index: Int?
            let confidence: String
            let memory_id: Int?
        }
        do {
            let data = try await makeRequest(
                "/user/intelligence/metadata-resolve",
                method: "POST",
                body: Body(filename: filename, candidates: candidates)
            )
            let result = try JSONDecoder().decode(Response.self, from: data)
            guard let index = result.best_index, index >= 0, index < candidates.count else {
                return nil
            }
            return MetadataResolution(bestIndex: index, memoryID: result.memory_id)
        } catch {
            return nil
        }
    }

    /// Reports that a user manually corrected a song's title/artist after
    /// Aria Lumi previously resolved it for this filename (see
    /// `IntelligenceSuggestionCache`). Fire-and-forget: failures are silent
    /// since this is a learning signal, not a user-facing action.
    func reportMetadataCorrection(memoryID: Int, title: String, artist: String) async {
        guard isLoggedIn, currentUser?.aiAssistedSuggestions == true else { return }
        struct Body: Encodable {
            let memory_id: Int
            let correction: [String: String]
        }
        _ = try? await makeRequest(
            "/user/intelligence/feedback",
            method: "POST",
            body: Body(memory_id: memoryID, correction: ["title": title, "artist": artist])
        )
    }
}
