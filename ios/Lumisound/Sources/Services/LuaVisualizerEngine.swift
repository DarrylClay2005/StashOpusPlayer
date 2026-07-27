import Foundation
import SwiftUI

// MARK: - LuaVisualizerEngine
//
// User/community-scriptable presentation for the "Live Spectrum" Now Playing
// artwork style (see `LiveSpectrumArtworkView`/`AudioVisualizerService`). The
// FFT analysis itself stays entirely native (there's no way to make a fresh
// Lua evaluation keep up with a 60fps render loop, and no need to — the
// analyzer already does real signal processing on the audio render thread).
// What a script controls is the LOOK: gradient color stops, sensitivity,
// smoothing, bar corner radius/spacing, mirroring — resolved ONCE when
// selected (same "resolve once, apply many times" contract as
// `LuaThemeEngine`/`LuaEffectEngine`), not re-evaluated per frame.
enum LuaVisualizerEngine {
    private static let subdirectory = "LuaVisualizers"

    static func bundledScripts() -> [LuaUserScriptLibrary.ScriptRef] {
        LuaUserScriptLibrary.bundledScripts(subdirectory: subdirectory)
    }

    static func userScripts() -> [LuaUserScriptLibrary.ScriptRef] {
        LuaUserScriptLibrary.userScripts(subdirectory: subdirectory)
    }

    @discardableResult
    static func importScript(source: String, suggestedName: String) throws -> LuaUserScriptLibrary.ScriptRef {
        try LuaUserScriptLibrary.importScript(source: source, suggestedName: suggestedName, subdirectory: subdirectory)
    }

    static func deleteUserScript(_ ref: LuaUserScriptLibrary.ScriptRef) {
        LuaUserScriptLibrary.deleteUserScript(ref)
    }

    struct Config: Decodable, Equatable {
        /// Hex gradient stops, bottom→top. At least 2 expected; fewer than 2
        /// falls back to the native default in `resolve(_:)`.
        var colors: [String]
        /// Multiplies each bar's raw 0...1 magnitude before clamping — >1
        /// makes quiet passages look busier, <1 calms down loud ones.
        var sensitivity: Double
        var barCornerRadius: Double
        var barSpacing: Double
        /// Renders the bar sequence mirrored (reversed) — a purely
        /// left/right cosmetic flip.
        var mirrored: Bool
    }

    enum EngineError: LocalizedError {
        case scriptNotReadable(String)
        var errorDescription: String? {
            switch self {
            case .scriptNotReadable(let name): return "Couldn't read the \u{201C}\(name)\u{201D} visualizer script."
            }
        }
    }

    static func resolve(_ ref: LuaUserScriptLibrary.ScriptRef) throws -> Config {
        guard let source = try? String(contentsOf: ref.url, encoding: .utf8) else {
            throw EngineError.scriptNotReadable(ref.displayName)
        }
        let wrapped = source + "\nreturn json.encode(visualizer)\n"
        return try LuaJSONBridge.run(wrapped, chunkName: ref.id, as: Config.self)
    }
}

// MARK: - LuaVisualizerStore
//
// Holds the currently-active scripted visualizer config (if any) so
// `LiveSpectrumArtworkView` can observe it without re-running Lua itself —
// mirrors `LuaThemeEngine`'s "resolve once, publish, re-resolve at launch"
// shape at a much smaller scale.
@MainActor
final class LuaVisualizerStore: ObservableObject {
    static let shared = LuaVisualizerStore()

    @Published private(set) var activeConfig: LuaVisualizerEngine.Config?
    @Published private(set) var activeScriptID: String?
    @Published private(set) var lastError: String?

    private static let key = "lua_active_visualizer_script"

    private init() {
        if let id = UserDefaults.standard.string(forKey: Self.key),
           let ref = (LuaVisualizerEngine.bundledScripts() + LuaVisualizerEngine.userScripts()).first(where: { $0.id == id }) {
            apply(ref, persist: false)
        }
    }

    @discardableResult
    func apply(_ ref: LuaUserScriptLibrary.ScriptRef, persist: Bool = true) -> Bool {
        do {
            let config = try LuaVisualizerEngine.resolve(ref)
            activeConfig = config
            activeScriptID = ref.id
            lastError = nil
            if persist {
                UserDefaults.standard.set(ref.id, forKey: Self.key)
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clear() {
        activeConfig = nil
        activeScriptID = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
