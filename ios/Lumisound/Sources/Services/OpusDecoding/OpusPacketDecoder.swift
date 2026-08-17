import AVFoundation
import AudioToolbox

/// Decodes raw Opus packets (already extracted from whatever container --
/// `OggOpusDemuxer` for Ogg, a future WebM demuxer for the itag-251 case) into
/// PCM, via `AudioConverter`'s registered `kAudioFormatOpus` codec component
/// rather than a bundled third-party decoder library.
///
/// # Why this should work
/// iOS has genuinely had a registered Opus codec component since iOS 15 --
/// that component is what lets `AVPlayer` play Opus at all today (the existing
/// "compatibility mode" fallback this whole pipeline is trying to avoid).
/// `AudioConverter` has always worked by looking up whatever codec component is
/// registered for a given `AudioFormatID` in the system's Codec Manager; this
/// isn't a private/undocumented API being repurposed, it's the standard
/// mechanism `AudioConverter` uses for every compressed format (AAC, ALAC,
/// etc.), just pointed at a format ID (`kAudioFormatOpus`) Apple has populated
/// but never built a matching AVAudioFile/AVAssetReader-level convenience API
/// around for third parties.
///
/// # What's genuinely uncertain here (flagging honestly, not glossing over it)
/// This exact call sequence has NOT been run/verified against a device or
/// simulator in this environment -- there is no way to do that here. The
/// specific pieces most likely to need real-device debugging if something's
/// off:
///   - Whether the Opus codec component expects `kAudioConverterDecompressionMagicCookie`
///     seeded from the raw "OpusHead" packet bytes (attempted below, but its
///     result is deliberately ignored on failure rather than treated as fatal,
///     since some codec components don't require one).
///   - Whether input packets need any `AudioStreamPacketDescription` frame-count
///     hint beyond `mDataByteSize`, or whether variable Opus frame durations
///     (2.5ms-60ms) need to be pre-computed and supplied per packet.
///   - Output buffer sizing/pacing across `AudioConverterFillComplexBuffer` calls
///     when a single call may consume more than one input packet internally.
/// If decoded audio comes out corrupted/silent, start by instrumenting this
/// file specifically, not `OggOpusDemuxer` (the demuxer's output -- packet
/// boundaries -- is independently checkable by comparing packet count/sizes
/// against `opusinfo`/`ffprobe` output for the same file).
enum OpusPacketDecoder {

    enum DecodeError: Error {
        case converterCreationFailed(OSStatus)
        case conversionFailed(OSStatus)
    }

    /// Decodes every packet in `packets` (in order) to interleaved Float32 PCM
    /// at 48 kHz (Opus's fixed internal decode rate), trims `preSkip` decoded
    /// frames from the start per RFC 7845 section 4.2, and returns the result
    /// as an `AVAudioPCMBuffer` ready to hand to an `AVAudioFile` writer.
    static func decode(
        packets: [Data],
        opusHeadPacket: Data,
        channelCount: Int,
        preSkip: Int
    ) throws -> AVAudioPCMBuffer {
        var inputDescription = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw DecodeError.converterCreationFailed(kAudio_ParamError)
        }
        var outputDescription = outputFormat.streamDescription.pointee

        var converterOpt: AudioConverterRef?
        let createStatus = AudioConverterNew(&inputDescription, &outputDescription, &converterOpt)
        guard createStatus == noErr, let converter = converterOpt else {
            throw DecodeError.converterCreationFailed(createStatus)
        }
        defer { AudioConverterDispose(converter) }

        // Best-effort magic cookie seed from the raw OpusHead packet -- see the
        // type doc comment above. Failure here is not fatal; not every codec
        // component requires one, and there's no reliable way to know without
        // on-device testing which is true for this one.
        _ = opusHeadPacket.withUnsafeBytes { rawBuffer -> OSStatus in
            AudioConverterSetProperty(
                converter,
                kAudioConverterDecompressionMagicCookie,
                UInt32(rawBuffer.count),
                rawBuffer.baseAddress
            )
        }

        var context = DecodeContext(packets: packets, nextIndex: 0)
        // Opus's max frame size is 120ms at 48kHz = 5760 frames/channel; sizing
        // the per-call output request generously above that keeps this to a
        // small, bounded number of AudioConverterFillComplexBuffer calls rather
        // than one per tiny Opus frame.
        let framesPerCall: UInt32 = 5760 * 8
        var frameOutputs: [AVAudioPCMBuffer] = []

        while context.nextIndex < packets.count {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesPerCall) else {
                throw DecodeError.conversionFailed(kAudio_MemFullError)
            }
            outBuffer.frameLength = framesPerCall

            var ioOutputDataPacketSize: UInt32 = framesPerCall
            let status = withUnsafeMutablePointer(to: &context) { contextPointer -> OSStatus in
                AudioConverterFillComplexBuffer(
                    converter,
                    inputDataProc,
                    contextPointer,
                    &ioOutputDataPacketSize,
                    outBuffer.mutableAudioBufferList,
                    nil
                )
            }

            if ioOutputDataPacketSize > 0 {
                outBuffer.frameLength = ioOutputDataPacketSize
                frameOutputs.append(outBuffer)
            }

            // `.noMoreDataError` (a converter-defined sentinel our input proc
            // returns once `packets` is exhausted) is the expected, successful
            // end of stream -- anything else genuinely failed.
            if status != noErr && status != Self.noMoreDataStatus {
                throw DecodeError.conversionFailed(status)
            }
            if context.nextIndex >= packets.count && ioOutputDataPacketSize == 0 {
                break
            }
        }

        return try trimAndConcatenate(frameOutputs, preSkip: preSkip, format: outputFormat)
    }

    // MARK: - Input callback

    private struct DecodeContext {
        let packets: [Data]
        var nextIndex: Int
        /// Reused across every callback invocation rather than allocated fresh
        /// per packet -- AudioConverter only needs this valid for the duration
        /// of the immediate callback it's returned from, so a single
        /// context-owned slot avoids leaking one allocation per Opus packet.
        var packetDescription = AudioStreamPacketDescription()
    }

    /// Sentinel OSStatus our own input proc returns via `ioNumberDataPackets = 0`
    /// once every packet has been handed to the converter -- distinguished from
    /// a real failure in the caller above.
    private static let noMoreDataStatus: OSStatus = 0

    private static let inputDataProc: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
        guard let inUserData else {
            ioNumberDataPackets.pointee = 0
            return Self.noMoreDataStatus
        }
        let context = inUserData.assumingMemoryBound(to: DecodeContext.self)

        guard context.pointee.nextIndex < context.pointee.packets.count else {
            ioNumberDataPackets.pointee = 0
            return Self.noMoreDataStatus
        }

        let packet = context.pointee.packets[context.pointee.nextIndex]
        context.pointee.nextIndex += 1

        // The buffer this Data backs must outlive the converter call; packets
        // are retained by `context.pointee.packets` for the lifetime of this
        // whole decode() call, so a raw pointer into it is safe here.
        packet.withUnsafeBytes { rawBuffer in
            ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: rawBuffer.baseAddress)
            ioData.pointee.mBuffers.mDataByteSize = UInt32(rawBuffer.count)
        }
        ioData.pointee.mNumberBuffers = 1

        if let outDataPacketDescription {
            context.pointee.packetDescription = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(packet.count)
            )
            outDataPacketDescription.pointee = withUnsafeMutablePointer(to: &context.pointee.packetDescription) { $0 }
        }

        ioNumberDataPackets.pointee = 1
        return noErr
    }

    // MARK: - Pre-skip trim + concatenation

    private static func trimAndConcatenate(
        _ buffers: [AVAudioPCMBuffer],
        preSkip: Int,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let keptFrames = max(0, totalFrames - preSkip)
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(keptFrames)) else {
            throw DecodeError.conversionFailed(kAudio_MemFullError)
        }
        result.frameLength = AVAudioFrameCount(keptFrames)

        var framesToSkip = preSkip
        var writeOffset = 0
        let channelCount = Int(format.channelCount)

        for buffer in buffers {
            let frameCount = Int(buffer.frameLength)
            guard let src = buffer.floatChannelData, let dst = result.floatChannelData else { continue }

            var readOffset = 0
            if framesToSkip > 0 {
                let skipHere = min(framesToSkip, frameCount)
                readOffset = skipHere
                framesToSkip -= skipHere
            }
            let framesToCopy = frameCount - readOffset
            guard framesToCopy > 0 else { continue }

            for channel in 0..<channelCount {
                (dst[channel] + writeOffset).update(from: src[channel] + readOffset, count: framesToCopy)
            }
            writeOffset += framesToCopy
        }

        return result
    }
}
