import XCTest
@testable import StashOpusPlayer

final class EQSystemTests: XCTestCase {

    // MARK: Test 1 — All 10 EQ bands correctly initialised

    func testEQBandCount() {
        let settings = AudioSettings()
        XCTAssertEqual(settings.eqBands.count, 10, "AudioSettings must expose exactly 10 EQ bands")
    }

    // MARK: Test 2 — EQPreset band values are within valid range (–12…12 dB)

    func testEQPresetBandRanges() {
        for preset in EQPreset.allCases {
            XCTAssertEqual(preset.bands.count, 10, "Preset \(preset.id) must have 10 bands")
            for band in preset.bands {
                XCTAssertTrue(
                    (-12.0...12.0).contains(band),
                    "Preset \(preset.id) has out-of-range band: \(band)"
                )
            }
        }
    }

    // MARK: Test 3 — Flat preset is all zeros

    func testFlatPresetIsAllZeros() {
        XCTAssertTrue(
            EQPreset.flat.bands.allSatisfy { $0 == 0 },
            "EQPreset.flat must be all zeros"
        )
    }

    // MARK: Test 4 — AudioEffectsService has all expected effects

    func testEffectsServiceHasAllPresets() {
        let expectedIDs = [
            "none", "bassboost", "nightcore", "vaporwave",
            "lofi", "lowpass", "soft",
            "electronic", "party", "radio", "cinema",
            "pop", "rock", "classical",
            "deep", "anime", "doubletime", "slowmo",
            "pitch_up", "pitch_down",
        ]
        for id in expectedIDs {
            XCTAssertNotNil(
                AudioEffectsService.effect(id: id),
                "Missing effect: \(id)"
            )
        }
    }

    // MARK: Test 5 — Bassboost has positive low-band values

    func testBassboostHasPositiveLowBands() {
        guard let effect = AudioEffectsService.effect(id: "bassboost") else {
            XCTFail("bassboost effect not found"); return
        }
        XCTAssertGreaterThan(effect.eqBands[0], 0, "Band 0 (32 Hz) should be boosted")
        XCTAssertGreaterThan(effect.eqBands[1], 0, "Band 1 (64 Hz) should be boosted")
        XCTAssertGreaterThan(effect.eqBands[2], 0, "Band 2 (125 Hz) should be boosted")
    }

    // MARK: Test 6 — Nightcore has positive speed and pitch

    func testNightcoreSpeedAndPitch() {
        guard let effect = AudioEffectsService.effect(id: "nightcore") else {
            XCTFail("nightcore effect not found"); return
        }
        XCTAssertGreaterThan(effect.speed, 1.0, "Nightcore speed must be > 1.0")
        XCTAssertGreaterThan(effect.pitchSemitones, 0, "Nightcore pitch must be positive")
    }

    // MARK: Test 7 — AudioSettings defaults are valid

    func testAudioSettingsDefaults() {
        let settings = AudioSettings()
        XCTAssertEqual(settings.volume, 1.0)
        XCTAssertEqual(settings.speed, 1.0)
        XCTAssertEqual(settings.pitchSemitones, 0.0)
        XCTAssertFalse(settings.equalizerEnabled)
        XCTAssertEqual(settings.eqBands.count, 10)
        XCTAssertEqual(settings.activeEffectID, "none")
    }

    // MARK: Test 8 — applyEffect(none) resets to defaults

    func testApplyNoneEffectResetsSettings() {
        var settings = AudioSettings()
        settings.speed = 1.25
        settings.pitchSemitones = 4.5
        guard let noneEffect = AudioEffectsService.effect(id: "none") else {
            XCTFail("none effect not found"); return
        }
        let reset = AudioEffectsService.apply(effect: noneEffect, to: settings)
        XCTAssertEqual(reset.speed, 1.0, "Speed must reset to 1.0 after applying 'none'")
        XCTAssertEqual(reset.pitchSemitones, 0.0, "Pitch must reset to 0.0 after applying 'none'")
    }

    // MARK: Test 9 — EQ band values stay within bounds after apply

    func testEffectBandValuesInRange() {
        for effect in AudioEffectsService.allEffects {
            for band in effect.eqBands {
                XCTAssertTrue(
                    (-12.0...12.0).contains(band),
                    "Effect \(effect.id) has out-of-range band: \(band)"
                )
            }
        }
    }

    // MARK: Test 10 — Speed values are in playable range

    func testEffectSpeedInRange() {
        for effect in AudioEffectsService.allEffects {
            XCTAssertTrue(
                (0.25...4.0).contains(effect.speed),
                "Effect \(effect.id) speed \(effect.speed) is outside playable range 0.25–4.0"
            )
        }
    }
}
