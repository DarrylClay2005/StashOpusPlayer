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

    // MARK: - Aria Lumi (built-in; see ios-bridge/intelligence.py)

    /// Asks Aria Lumi (the bridge's AI-assisted metadata resolver) to pick
    /// the best candidate for a local file's metadata. Runs for every
    /// signed-in user unconditionally — no per-user opt-in anymore (see
    /// `AccountView`'s "Aria Lumi" section, no longer a toggle). Returns
    /// `nil` whenever the user is logged out, the network call fails, or she
    /// has no confident pick — in every case the caller falls back to its
    /// existing exact-match-or-first-result heuristic unchanged.
    func resolveMetadata(filename: String, candidates: [MetadataCandidate]) async -> MetadataResolution? {
        guard isLoggedIn, !candidates.isEmpty else {
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
        guard isLoggedIn else { return }
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

    /// Asks Aria Lumi for one short spoken DJ transition line into
    /// `nextTitle`/`nextArtist`, for `AIDJService` to speak aloud. `nil`
    /// whenever logged out, the call fails, or she has nothing to say —
    /// the caller just plays on with no spoken intro in that case.
    func fetchDJTransitionBlurb(
        nextTitle: String, nextArtist: String?,
        previousTitle: String?, previousArtist: String?
    ) async -> String? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable {
            let next_title: String
            let next_artist: String?
            let previous_title: String?
            let previous_artist: String?
        }
        struct Response: Decodable {
            let blurb: String?
        }
        do {
            let data = try await makeRequest(
                "/user/ai-dj/transition",
                method: "POST",
                body: Body(
                    next_title: nextTitle, next_artist: nextArtist,
                    previous_title: previousTitle, previous_artist: previousArtist
                )
            )
            return try JSONDecoder().decode(Response.self, from: data).blurb
        } catch {
            return nil
        }
    }

    /// Fetches today's Aria's Daily Pick — cached server-side per user per
    /// UTC calendar day (see `/user/aria/daily-pick` in main.py), so calling
    /// this more than once in the same day is free and never costs an
    /// extra Gemini call. Populates `ariaDailyPick`; leaves it untouched on
    /// failure so a transient network error doesn't blank out an
    /// already-loaded pick.
    func fetchAriaDailyPick() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/aria/daily-pick")
            ariaDailyPick = try JSONDecoder().decode(AriaDailyPick.self, from: data)
        } catch {
            appWarn("fetchAriaDailyPick: \(error.localizedDescription)", category: "network")
        }
    }

    /// Fetches (or triggers, on a first-ever request for this album) a
    /// short Aria Lumi liner-notes blurb for `artist`/`album` — cached
    /// server-side per album, not per user, so most calls are free (see
    /// `/music/liner-notes` in main.py). `nil` when logged out, the album
    /// isn't recognized/confident enough, or the request fails.
    func fetchLinerNotes(artist: String, album: String) async -> String? {
        guard isLoggedIn,
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        do {
            let data = try await makeRequest("/music/liner-notes?artist=\(encodedArtist)&album=\(encodedAlbum)")
            struct Response: Decodable { let blurb: String? }
            return try JSONDecoder().decode(Response.self, from: data).blurb
        } catch {
            return nil
        }
    }
}
