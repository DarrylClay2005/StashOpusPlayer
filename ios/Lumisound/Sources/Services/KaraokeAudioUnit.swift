import AVFoundation
import AudioToolbox

/// Holds the tunable state for `KaraokeAudioUnit`'s render block: a plain
/// reference type captured directly by the block instead of `self` (the
/// `AUAudioUnit`), matching Apple's own AUv3 sample-code pattern of a
/// lightweight "kernel" object so the realtime render path never touches
/// AUAudioUnit/ARC machinery.
final class KaraokeKernel {
    var level: Float = 1.0
    var bypassed = false
}

/// In-process Audio Unit performing real-time stereo center-channel
/// cancellation: out_L = (L−R)×0.5×level, out_R = (R−L)×0.5×level — silences
/// audio panned dead-center (typically lead vocals) while leaving hard-panned
/// content (instruments) intact.
///
/// This replaces an earlier, fundamentally broken implementation that tried
/// to achieve the same effect by mutating a buffer inside `installTap`'s
/// callback (see `AudioVisualizerService`'s tap for the *correct* use of
/// taps — read-only monitoring). Taps never feed their buffer back into the
/// signal path, so that mutation had zero effect on what was actually sent to
/// the audio hardware: `isKaraokeActive` flipped on and the DSP genuinely
/// ran, but the user never heard any difference. This class is a real insert
/// node instead, wired between `mainMixerNode` and `outputNode` in
/// `AudioPlayerManager+EngineConfig.swift`.
///
/// Constructed directly via `try KaraokeAudioUnit(componentDescription:)`
/// after registering it with `AUAudioUnit.registerSubclass` — this unit is
/// only ever used internally by `AudioPlayerManager`, never discovered by
/// another host, so the full asynchronous `AVAudioUnit.instantiate` dance
/// (needed to get a graph-attachable `AVAudioUnit` wrapper for a custom
/// component) is unavoidable, but the registration only needs to run once.
final class KaraokeAudioUnit: AUAudioUnit {

    private let kernel = KaraokeKernel()
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!

    /// 0 = no cancellation, 1 = full cancellation. Mirrors `AudioEffect.specialMode`'s level.
    var level: Float {
        get { kernel.level }
        set { kernel.level = newValue }
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44100, channels: 2)!
        let inputBus = try AUAudioUnitBus(format: format)
        let outputBus = try AUAudioUnitBus(format: format)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    // Captured by the AU host (not necessarily the host app's engine's own
    // bypass path) — a custom AUAudioUnit must honor bypass itself inside the
    // render block, unlike Apple's system units which handle it internally.
    override var shouldBypassEffect: Bool {
        get { kernel.bypassed }
        set { kernel.bypassed = newValue }
    }

    // Named distinctly from `renderBlock` — AUAudioUnit already declares a
    // public `renderBlock` property (a higher-level `AURenderBlock` wrapper
    // derived from `internalRenderBlock`); reusing that name here would
    // accidentally override it with the wrong type/access level.
    private lazy var cachedInternalRenderBlock: AUInternalRenderBlock = { [kernel] _, timestamp, frameCount, _, outputData, _, pullInputBlock in
        guard let pullInputBlock else { return kAudioUnitErr_NoConnection }

        var pullFlags: AudioUnitRenderActionFlags = []
        let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
        guard status == noErr else { return status }
        guard !kernel.bypassed else { return noErr }

        let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
        guard bufferList.count >= 2,
              let leftRaw = bufferList[0].mData,
              let rightRaw = bufferList[1].mData
        else { return noErr }

        let left = leftRaw.assumingMemoryBound(to: Float.self)
        let right = rightRaw.assumingMemoryBound(to: Float.self)
        let scale = 0.5 * kernel.level
        let n = Int(frameCount)
        for i in 0 ..< n {
            let l = left[i]
            let r = right[i]
            left[i]  = (l - r) * scale
            right[i] = (r - l) * scale
        }
        return noErr
    }

    override var internalRenderBlock: AUInternalRenderBlock { cachedInternalRenderBlock }
}

extension AudioComponentDescription {
    /// Unique in-process component identity for `KaraokeAudioUnit` — never
    /// registered/discovered outside this app, so the four-char codes just
    /// need to be internally unique, not globally reserved.
    static var karaokeCancellation: AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCharCode("krok"),
            componentManufacturer: fourCharCode("Lumi"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}
