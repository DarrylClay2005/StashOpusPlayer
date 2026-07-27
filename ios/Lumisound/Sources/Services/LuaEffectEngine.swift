import Foundation

// MARK: - LuaEffectEngine
//
// User/community-scriptable audio effect presets — the Lua-scripted
// counterpart to `AudioEffectsService`'s 27 fixed native presets. A script
// assigns a global `effect` table (id, name, icon, eq_bands, eq_enabled,
// speed, pitch_semitones, special_mode) computed however the author likes —
// loops, math, conditionals — rather than 10 hardcoded dB values. The
// resolved result is a real `AudioEffect`, applied through the exact same
// `AudioPlayerManager.applyEffect(_:)` a native preset goes through — no
// parallel effect-application path.
enum LuaEffectEngine {
    private static let subdirectory = "LuaEffects"

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

    /// Looks a script up by its `AudioEffect.id` (`"lua:<script id>"`) across
    /// both bundled and user scripts — used to re-resolve a previously
    /// active Lua effect (e.g. after an app relaunch or when restarting a
    /// dynamic special mode; see `AudioPlayerManager.reapplyActiveEffect`).
    static func scriptRef(forEffectID effectID: String) -> LuaUserScriptLibrary.ScriptRef? {
        guard effectID.hasPrefix("lua:") else { return nil }
        let scriptID = String(effectID.dropFirst("lua:".count))
        return (bundledScripts() + userScripts()).first { $0.id == scriptID }
    }

    // MARK: - Resolution

    private struct EffectConfig: Decodable {
        struct SpecialModeConfig: Decodable {
            var type: String
            var hz: Double?
            var freq: Double?
            var depth: Double?
            var pitchDepth: Double?
        }
        var id: String
        var name: String
        var icon: String
        var eqBands: [Float]
        var eqEnabled: Bool
        var speed: Float
        var pitchSemitones: Float
        var specialMode: SpecialModeConfig?
    }

    enum EngineError: LocalizedError {
        case scriptNotReadable(String)
        case invalidBandCount(Int)

        var errorDescription: String? {
            switch self {
            case .scriptNotReadable(let name):
                return "Couldn't read the \u{201C}\(name)\u{201D} effect script."
            case .invalidBandCount(let count):
                return "Effect script returned \(count) EQ bands \u{2014} expected exactly 10."
            }
        }
    }

    /// Runs `ref`'s script and resolves it into a real `AudioEffect`, ready
    /// to hand to `AudioPlayerManager.applyEffect(_:)`. The `id` on the
    /// returned effect is always `"lua:<script id>"` (ignoring whatever `id`
    /// the script itself set) so it can never collide with a native preset's
    /// id and is always traceable back to its source script.
    static func resolve(_ ref: LuaUserScriptLibrary.ScriptRef) throws -> AudioEffect {
        guard let source = try? String(contentsOf: ref.url, encoding: .utf8) else {
            throw EngineError.scriptNotReadable(ref.displayName)
        }
        let wrapped = source + "\nreturn json.encode(effect)\n"
        let config = try LuaJSONBridge.run(wrapped, chunkName: ref.id, as: EffectConfig.self)
        guard config.eqBands.count == 10 else {
            throw EngineError.invalidBandCount(config.eqBands.count)
        }

        var specialMode = AudioEffectSpecialMode.none
        if let sm = config.specialMode {
            switch sm.type {
            case "rotation":
                specialMode = .rotation(hz: sm.hz ?? 0.18)
            case "tremolo":
                specialMode = .tremolo(freq: sm.freq ?? 4.0, depth: Float(sm.depth ?? 0.45))
            case "vibrato":
                specialMode = .vibrato(freq: sm.freq ?? 4.5, depth: sm.pitchDepth ?? 0.35)
            default:
                break
            }
        }

        return AudioEffect(
            id: "lua:\(ref.id)",
            name: config.name,
            icon: config.icon,
            eqBands: config.eqBands,
            eqEnabled: config.eqEnabled,
            speed: config.speed,
            pitchSemitones: config.pitchSemitones,
            specialMode: specialMode
        )
    }
}
