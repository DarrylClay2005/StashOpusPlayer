import CoreMotion
import AVFoundation

/// Wraps `CMHeadphoneMotionManager` to drive `AVAudioEnvironmentNode.listenerAngularOrientation`
/// for head-tracked Spatial Audio. Head tracking only works with compatible Apple
/// headphones (AirPods Pro/Max, some Beats models) — on any other output,
/// `isHeadTrackingAvailable` is false and `AudioPlayerManager` falls back to a
/// static anchored source (still HRTF-spatialized, just without rotation).
@MainActor
final class SpatialAudioService {
    static let shared = SpatialAudioService()

    private let motionManager = CMHeadphoneMotionManager()

    /// Called with the latest head orientation (main queue) while tracking is active.
    var onOrientationUpdate: ((AVAudio3DAngularOrientation) -> Void)?

    var isHeadTrackingAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    private init() {}

    func startTracking() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion else {
                if let error {
                    appWarn("SpatialAudioService: motion update error: \(error.localizedDescription)", category: "audio")
                }
                return
            }
            // CMHeadphoneMotionManager reports attitude in radians; AVAudioEnvironmentNode
            // wants degrees. Yaw/pitch are negated so an anchored source stays fixed in
            // space as the listener turns their head (the listener orientation rotates
            // opposite the head, not with it).
            let orientation = AVAudio3DAngularOrientation(
                yaw: Float(-motion.attitude.yaw * 180 / .pi),
                pitch: Float(-motion.attitude.pitch * 180 / .pi),
                roll: Float(motion.attitude.roll * 180 / .pi)
            )
            self.onOrientationUpdate?(orientation)
        }
    }

    func stopTracking() {
        guard motionManager.isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
        onOrientationUpdate?(AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0))
    }
}
