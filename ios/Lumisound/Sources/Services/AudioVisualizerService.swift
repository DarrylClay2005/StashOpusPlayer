import Accelerate
import AVFoundation

/// Computes a real-time frequency spectrum from the live audio graph, for
/// the "Live Spectrum" Now Playing artwork style. Taps `mainMixerNode` (see
/// `AudioPlayerManager.startVisualizerTap`) rather than decoding/analyzing
/// anything separately, so it reacts to exactly what's actually audible
/// (effects, EQ, crossfade included) — entirely on-device, no server.
@MainActor
final class AudioVisualizerService: ObservableObject {
    static let shared = AudioVisualizerService()

    static let barCount = 24

    /// Smoothed per-bar magnitude, 0...1.
    @Published private(set) var magnitudes: [Float] = Array(repeating: 0, count: barCount)

    private let fftSize = 2048
    private let log2n: vDSP_Length = 11 // 2^11 == 2048
    private let fftSetup: FFTSetup?

    private init() {
        fftSetup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    func start() {
        AudioPlayerManager.shared?.startVisualizerTap { [weak self] buffer in
            self?.process(buffer: buffer)
        }
    }

    func stop() {
        AudioPlayerManager.shared?.stopVisualizerTap()
        magnitudes = Array(repeating: 0, count: Self.barCount)
    }

    /// Runs on the audio render thread (the tap's callback), not the main
    /// thread — `nonisolated` so it can execute there directly instead of
    /// needing to hop actors just to start; only the final publish step
    /// hops back to the main actor.
    nonisolated private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let available = Int(buffer.frameLength)
        guard available > 0 else { return }

        let n = min(available, fftSize)
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        let samples = channelData[0]
        for i in 0..<n { real[i] = samples[i] }

        guard let fftSetup else { return }
        var bars = [Float](repeating: 0, count: Self.barCount)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                let halfSize = fftSize / 2
                var fftMagnitudes = [Float](repeating: 0, count: halfSize)
                fftMagnitudes.withUnsafeMutableBufferPointer { magPtr in
                    guard let magBase = magPtr.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magBase, 1, vDSP_Length(halfSize))
                }

                // Logarithmically-spaced bins — otherwise almost all musical
                // energy (bass/mid) collapses into the first couple of bars
                // and everything above that reads as flat silence.
                for bar in 0..<Self.barCount {
                    let lowFrac = pow(Double(bar) / Double(Self.barCount), 2)
                    let highFrac = pow(Double(bar + 1) / Double(Self.barCount), 2)
                    let lowBin = max(1, Int(lowFrac * Double(halfSize)))
                    let highBin = max(lowBin + 1, min(halfSize, Int(highFrac * Double(halfSize))))
                    guard lowBin < highBin else { continue }
                    let slice = fftMagnitudes[lowBin..<highBin]
                    let avg = slice.reduce(0, +) / Float(slice.count)
                    bars[bar] = min(1, max(0, log10(avg + 1) / 4))
                }
            }
        }

        Task { @MainActor [weak self] in
            self?.applySmoothed(bars)
        }
    }

    private func applySmoothed(_ new: [Float]) {
        guard new.count == magnitudes.count else { return }
        for i in 0..<magnitudes.count {
            magnitudes[i] = magnitudes[i] * 0.55 + new[i] * 0.45
        }
    }
}
