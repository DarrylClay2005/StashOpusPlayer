import Foundation

// MARK: - AudioEffect

struct AudioEffect: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let icon: String           // SF Symbol name
    var eqBands: [Float]       // 10 values in dB (32Hz–16kHz)
    var eqEnabled: Bool        // whether EQ should be active
    var speed: Float           // 1.0 = normal playback speed
    var pitchSemitones: Float  // 0.0 = no pitch shift
}

// MARK: - AudioEffectsService

enum AudioEffectsService {

    // MARK: All Presets

    /// All 19 implementable effects (8d / karaoke / tremolo / vibrato / earrape skipped
    /// because they require DSP primitives outside AVAudioUnitEQ / AVAudioUnitTimePitch).
    static let allEffects: [AudioEffect] = [
        none,
        bassboost,
        nightcore,
        vaporwave,
        lofi,
        lowpass,
        soft,
        electronic,
        party,
        radio,
        cinema,
        pop,
        rock,
        classical,
        deep,
        anime,
        doubletime,
        slowmo,
        pitchUp,
        pitchDown,
    ]

    // MARK: Preset Definitions

    /// Flat — all defaults, no processing.
    static let none = AudioEffect(
        id: "none",
        name: "None",
        icon: "waveform",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// bassboost: equalizer(bands=[(0,0.32),(1,0.24),(2,0.12)])
    /// iOS[0] = avg(0.32,0.24)*12 = 3.4  iOS[1] = 0.12*12 = 1.4
    static let bassboost = AudioEffect(
        id: "bassboost",
        name: "Bass Boost",
        icon: "speaker.wave.3.fill",
        eqBands: [3.8, 2.9, 1.4, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// nightcore: timescale(speed=1.25, pitch=1.3)
    /// pitch: 12*log2(1.3) = +4.5 semitones
    static let nightcore = AudioEffect(
        id: "nightcore",
        name: "Nightcore",
        icon: "moon.stars.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 1.25,
        pitchSemitones: 4.5
    )

    /// vaporwave: timescale(speed=0.8, pitch=0.8)
    /// pitch: 12*log2(0.8) = -3.9 semitones
    static let vaporwave = AudioEffect(
        id: "vaporwave",
        name: "Vaporwave",
        icon: "sunset.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 0.8,
        pitchSemitones: -3.9
    )

    /// lofi: lowpass(smoothing=35.0) + timescale(speed=0.94, pitch=0.96)
    /// pitch: 12*log2(0.96) = -0.7 semitones
    /// Lowpass simulated as high-frequency rolloff: band[8]=-3.0, band[9]=-8.0
    static let lofi = AudioEffect(
        id: "lofi",
        name: "Lo-Fi",
        icon: "radio.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, -3.0, -8.0],
        eqEnabled: true,
        speed: 0.94,
        pitchSemitones: -0.7
    )

    /// lowpass: lowpass(smoothing=20.0)
    /// band[8]=-4.0, band[9]=-8.0
    static let lowpass = AudioEffect(
        id: "lowpass",
        name: "Low Pass",
        icon: "arrow.down.to.line",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, -4.0, -8.0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// soft: lowpass(smoothing=25.0)
    /// band[7]=-1.5, band[8]=-3.5, band[9]=-7.0
    static let soft = AudioEffect(
        id: "soft",
        name: "Soft",
        icon: "cloud.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, -1.5, -3.5, -7.0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// electronic: equalizer(bands=[(0,0.12),(1,0.10),(4,-0.05),(8,0.08),(10,0.14)])
    /// iOS[0]=avg(0.12,0.10)*12=1.3  iOS[2]=avg(0,-0.05)*12=-0.3
    /// iOS[5]=avg(0.08,0)*12=0.5     iOS[6]=0.14*12=1.7
    static let electronic = AudioEffect(
        id: "electronic",
        name: "Electronic",
        icon: "bolt.fill",
        eqBands: [1.3, 0, -0.3, 0, 0, 0.5, 1.7, 0, 0, 0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// party: equalizer(bands=[(0,0.25),(1,0.18),(2,0.08),(9,0.10)])
    /// iOS[0]=avg(0.25,0.18)*12=2.6  iOS[1]=0.08*12=1.0
    /// iOS[5]=avg(0,0.10)*12=0.6
    static let party = AudioEffect(
        id: "party",
        name: "Party",
        icon: "party.popper.fill",
        eqBands: [2.6, 1.0, 0, 0, 0, 0.6, 0, 0, 0, 0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// radio: equalizer(bands=[(0,-0.18),(1,-0.10),(4,0.12),(5,0.12),(10,-0.12)]) + lowpass(18.0)
    /// iOS[0]=avg(-0.18,-0.10)*12=-1.7  iOS[2]=avg(0,0.12)*12=0.7
    /// iOS[3]=0.12*12=1.4               iOS[6]=-0.12*12=-1.4
    /// lowpass(18.0) → heavy: band[8]=-5.0, band[9]=-8.0
    static let radio = AudioEffect(
        id: "radio",
        name: "Radio",
        icon: "antenna.radiowaves.left.and.right",
        eqBands: [-1.7, 0, 0.7, 1.4, 0, 0, -1.4, 0, -5.0, -8.0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// cinema: equalizer(bands=[(0,0.18),(1,0.12),(8,0.08),(9,0.10)])
    /// iOS[0]=avg(0.18,0.12)*12=1.8  iOS[5]=avg(0.08,0.10)*12=1.1
    static let cinema = AudioEffect(
        id: "cinema",
        name: "Cinema",
        icon: "film.fill",
        eqBands: [1.8, 0, 0, 0, 0, 1.1, 0, 0, 0, 0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// pop: converted from 15-band bot definition
    /// iOS[0]=0.0  iOS[1]=2.4  iOS[2]=2.7  iOS[3]=1.2  iOS[4]=-0.3
    /// iOS[5]=-1.2  iOS[6]=-0.6  iOS[7]=0.0  iOS[8]=1.8  iOS[9]=1.2
    static let pop = AudioEffect(
        id: "pop",
        name: "Pop",
        icon: "music.mic",
        eqBands: [0.0, 2.4, 2.7, 1.2, -0.3, -1.2, -0.6, 0.0, 1.8, 1.2],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// rock: converted from 15-band bot definition
    /// iOS[0]=3.3  iOS[1]=1.2  iOS[2]=-1.5  iOS[3]=-1.2  iOS[4]=0.6
    /// iOS[5]=3.9  iOS[6]=3.6  iOS[7]=2.4   iOS[8]=0.9   iOS[9]=0.0
    static let rock = AudioEffect(
        id: "rock",
        name: "Rock",
        icon: "guitars.fill",
        eqBands: [3.3, 1.2, -1.5, -1.2, 0.6, 3.9, 3.6, 2.4, 0.9, 0.0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// classical: converted from 15-band bot definition
    /// iOS[0]=1.2  iOS[1]=0.6  iOS[2]=-0.3  iOS[3]=-0.6  iOS[4]=-0.6
    /// iOS[5]=-0.6  iOS[6]=0.0  iOS[7]=0.6  iOS[8]=1.5   iOS[9]=2.4
    static let classical = AudioEffect(
        id: "classical",
        name: "Classical",
        icon: "pianokeys",
        eqBands: [1.2, 0.6, -0.3, -0.6, -0.6, -0.6, 0.0, 0.6, 1.5, 2.4],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: 0.0
    )

    /// deep: equalizer(bands=[(0,0.5),(1,0.4),(2,0.3)]) + timescale(pitch=0.8)
    /// iOS[0]=avg(0.5,0.4)*12=5.4  iOS[1]=0.3*12=3.6
    /// pitch: 12*log2(0.8) = -3.9 semitones
    static let deep = AudioEffect(
        id: "deep",
        name: "Deep",
        icon: "waveform.path",
        eqBands: [5.4, 3.6, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: true,
        speed: 1.0,
        pitchSemitones: -3.9
    )

    /// anime: timescale(speed=1.4, pitch=1.5)
    /// pitch: 12*log2(1.5) = +7.0 semitones
    static let anime = AudioEffect(
        id: "anime",
        name: "Anime",
        icon: "star.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 1.4,
        pitchSemitones: 7.0
    )

    /// doubletime: timescale(speed=2.0, pitch=1.0) — speed only, no EQ, no pitch shift
    static let doubletime = AudioEffect(
        id: "doubletime",
        name: "Double Time",
        icon: "forward.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 2.0,
        pitchSemitones: 0.0
    )

    /// slowmo: timescale(speed=0.5, pitch=1.0) — speed only, no EQ, no pitch shift
    static let slowmo = AudioEffect(
        id: "slowmo",
        name: "Slow Mo",
        icon: "backward.fill",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 0.5,
        pitchSemitones: 0.0
    )

    /// pitch_up: timescale(speed=1.0, pitch=1.3)
    /// pitch: 12*log2(1.3) = +4.5 semitones
    static let pitchUp = AudioEffect(
        id: "pitch_up",
        name: "Pitch Up",
        icon: "arrow.up",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 1.0,
        pitchSemitones: 4.5
    )

    /// pitch_down: timescale(speed=1.0, pitch=0.7)
    /// pitch: 12*log2(0.7) = -6.1 semitones
    static let pitchDown = AudioEffect(
        id: "pitch_down",
        name: "Pitch Down",
        icon: "arrow.down",
        eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        eqEnabled: false,
        speed: 1.0,
        pitchSemitones: -6.1
    )

    // MARK: Lookup

    /// Returns the effect matching the given id, or nil if not found.
    static func effect(id: String) -> AudioEffect? {
        allEffects.first { $0.id == id }
    }

    // MARK: Apply

    /// Copies `settings`, applies the effect's EQ, speed, and pitch onto it,
    /// and stamps `activeEffectID`. The caller should assign the return value
    /// back to `AudioPlayerManager.audioSettings`.
    static func apply(effect: AudioEffect, to settings: AudioSettings) -> AudioSettings {
        var s = settings
        s.speed = effect.speed
        s.pitchSemitones = effect.pitchSemitones
        s.equalizerEnabled = effect.eqEnabled
        s.eqBands = effect.eqBands
        // Mark the preset as custom so the EQ chip strip doesn't highlight a
        // mismatched preset while an audio effect is active.
        s.eqPreset = effect.eqEnabled ? .custom : .flat
        s.activeEffectID = effect.id
        return s
    }
}
