import Foundation

/// Parses a raw Ogg-Opus file (RFC 7845 -- what the bridge produces whenever the
/// user's preferred format is explicitly "Opus") into its identification header
/// fields and the ordered sequence of raw Opus packets, entirely independent of
/// AVFoundation. This exists because `AVURLAsset`/`AVAssetReader` cannot open an
/// Ogg container at all on iOS -- there's no lower-level API gap to work around,
/// Apple simply never shipped an Ogg demuxer for third-party apps to call into.
///
/// Ogg's page format (RFC 3533) is deliberately simple and fully specified here;
/// this is NOT the uncertain part of the client-side Opus pipeline -- see
/// `OpusPacketDecoder` for the part that actually carries real risk.
enum OggOpusDemuxer {

    struct Header {
        /// From the "OpusHead" packet. Channel count as coded (mono/stereo almost
        /// always in practice for downloaded tracks).
        let channelCount: Int
        /// Number of decoded samples (at 48 kHz, Opus's fixed internal rate) to
        /// discard from the very start of playback -- encoder priming/lookahead,
        /// NOT a bug if you see the first few ms trimmed.
        let preSkip: Int
        /// Informational only (what the encoder was originally fed) -- decoded
        /// PCM is always produced at 48 kHz regardless of this value.
        let inputSampleRate: UInt32
        /// Q7.8 fixed-point output gain, in dB units of 1/256 dB. Almost always 0
        /// for tracks that weren't explicitly loudness-tagged at encode time.
        let outputGainQ78: Int16
    }

    struct Result {
        let header: Header
        /// The raw "OpusHead" packet bytes -- needed by `OpusPacketDecoder` as a
        /// best-effort magic-cookie seed, kept separate from `header` (which is
        /// already parsed) since the decoder needs the original bytes, not the
        /// parsed fields.
        let opusHeadPacketData: Data
        /// Every raw Opus audio packet, in decode order, with OpusHead/OpusTags
        /// already stripped out -- ready to hand one-by-one to `OpusPacketDecoder`.
        let packets: [Data]
    }

    enum DemuxError: Error {
        case notAnOggFile
        case missingOpusHead
        case truncated
        case unsupportedChannelMapping(Int)
    }

    /// Parses `data` end to end. Ogg files can in principle multiplex several
    /// logical streams by serial number; a file the bridge produced for a single
    /// audio download only ever has one, so this collapses everything by the
    /// FIRST serial number seen (the one whose first packet is "OpusHead") and
    /// ignores pages belonging to any other stream, rather than implementing
    /// full multi-stream demuxing multiplexing/chaining support that no
    /// real-world download from this pipeline will ever exercise.
    static func parse(_ data: Data) throws -> Result {
        var offset = data.startIndex
        var header: Header?
        var opusHeadPacketData: Data?
        var sawOpusTags = false
        var targetSerial: UInt32?
        var packets: [Data] = []

        // A packet can be split across consecutive Ogg pages (any segment of
        // exactly 255 bytes means "more of this packet follows on the next
        // segment/page"); this carries a partially-assembled packet across
        // page boundaries for that stream.
        var pendingPacket = Data()

        while offset < data.endIndex {
            guard let page = try readPage(data, at: &offset) else { break }

            if let targetSerial, page.serial != targetSerial {
                // A page from some other multiplexed stream (shouldn't happen for
                // these downloads, but skip rather than misinterpret its bytes).
                continue
            }

            for (index, segment) in page.packets.enumerated() {
                let isFinalSegmentOfPage = index == page.packets.count - 1
                pendingPacket.append(segment.bytes)

                // A packet is "complete" once a segment shorter than 255 bytes
                // terminates it, OR once the page itself says this was the last
                // lacing value and it happened to be a full 255-byte segment that
                // is also flagged as ending exactly on a page boundary (the
                // `continued` flag on the NEXT page tells us definitively; until
                // then treat a page-ending 255-byte segment as still-pending).
                guard segment.bytes.count < 255 || (isFinalSegmentOfPage && !page.headerType.continuesOnNextPage) else {
                    continue
                }

                let completed = pendingPacket
                pendingPacket = Data()

                if header == nil {
                    guard let parsedHeader = parseOpusHead(completed) else {
                        throw DemuxError.missingOpusHead
                    }
                    header = parsedHeader
                    opusHeadPacketData = completed
                    targetSerial = page.serial
                    continue
                }
                if !sawOpusTags {
                    // OpusTags (Vorbis-comment-style metadata) -- not needed for
                    // playback, just skip it.
                    sawOpusTags = true
                    continue
                }
                packets.append(completed)
            }
        }

        guard let header, let opusHeadPacketData else { throw DemuxError.missingOpusHead }
        guard header.channelCount == 1 || header.channelCount == 2 else {
            // Channel mapping family >0 (surround/ambisonics) needs a channel
            // mapping table this parser doesn't read -- real-world downloads
            // from a music-streaming source are always mono or stereo.
            throw DemuxError.unsupportedChannelMapping(header.channelCount)
        }
        return Result(header: header, opusHeadPacketData: opusHeadPacketData, packets: packets)
    }

    // MARK: - Page parsing

    private struct HeaderTypeFlags {
        let continuesOnNextPage: Bool
        let isFirstPage: Bool
        let isLastPage: Bool

        init(_ byte: UInt8) {
            continuesOnNextPage = (byte & 0x01) != 0
            isFirstPage = (byte & 0x02) != 0
            isLastPage = (byte & 0x04) != 0
        }
    }

    private struct Page {
        let headerType: HeaderTypeFlags
        let serial: UInt32
        /// Reconstructed lacing-value segments for this page, in order -- NOT
        /// yet reassembled into packets (a segment boundary isn't always a
        /// packet boundary, see the 255-byte continuation rule above).
        let packets: [(bytes: Data)]
    }

    /// Reads one Ogg page starting at `offset`, advancing `offset` past it.
    /// Returns `nil` at clean end-of-data; throws on a malformed/truncated page.
    private static func readPage(_ data: Data, at offset: inout Data.Index) throws -> Page? {
        guard offset < data.endIndex else { return nil }
        guard data.distance(from: offset, to: data.endIndex) >= 27 else {
            throw DemuxError.truncated
        }

        let capture = data[offset..<data.index(offset, offsetBy: 4)]
        guard capture.elementsEqual("OggS".utf8) else { throw DemuxError.notAnOggFile }

        var cursor = data.index(offset, offsetBy: 4)
        cursor = data.index(cursor, offsetBy: 1) // stream_structure_version, always 0

        let headerTypeByte = data[cursor]
        let headerType = HeaderTypeFlags(headerTypeByte)
        cursor = data.index(cursor, offsetBy: 1)

        cursor = data.index(cursor, offsetBy: 8) // granule_position -- not needed for decode

        let serial = readUInt32LE(data, at: cursor)
        cursor = data.index(cursor, offsetBy: 4)

        cursor = data.index(cursor, offsetBy: 4) // page_sequence_number -- not needed
        cursor = data.index(cursor, offsetBy: 4) // CRC32 checksum -- trusted, not verified

        let segmentCount = Int(data[cursor])
        cursor = data.index(cursor, offsetBy: 1)

        guard data.distance(from: cursor, to: data.endIndex) >= segmentCount else {
            throw DemuxError.truncated
        }
        let lacingValues = data[cursor..<data.index(cursor, offsetBy: segmentCount)].map { Int($0) }
        cursor = data.index(cursor, offsetBy: segmentCount)

        var segments: [(bytes: Data)] = []
        for length in lacingValues {
            guard data.distance(from: cursor, to: data.endIndex) >= length else {
                throw DemuxError.truncated
            }
            let end = data.index(cursor, offsetBy: length)
            segments.append((bytes: data[cursor..<end]))
            cursor = end
        }

        offset = cursor
        return Page(headerType: headerType, serial: serial, packets: segments)
    }

    private static func readUInt32LE(_ data: Data, at index: Data.Index) -> UInt32 {
        let b0 = UInt32(data[index])
        let b1 = UInt32(data[data.index(index, offsetBy: 1)])
        let b2 = UInt32(data[data.index(index, offsetBy: 2)])
        let b3 = UInt32(data[data.index(index, offsetBy: 3)])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private static func readUInt16LE(_ data: Data, at index: Data.Index) -> UInt16 {
        let b0 = UInt16(data[index])
        let b1 = UInt16(data[data.index(index, offsetBy: 1)])
        return b0 | (b1 << 8)
    }

    // MARK: - OpusHead parsing

    /// Parses the mandatory-first "OpusHead" packet (RFC 7845 section 5.1).
    /// Only channel mapping family 0 (mono/stereo, no channel mapping table) is
    /// supported -- see `DemuxError.unsupportedChannelMapping`.
    private static func parseOpusHead(_ packet: Data) -> Header? {
        guard packet.count >= 19 else { return nil }
        let magic = packet.prefix(8)
        guard magic.elementsEqual("OpusHead".utf8) else { return nil }

        var cursor = packet.index(packet.startIndex, offsetBy: 8)
        cursor = packet.index(cursor, offsetBy: 1) // version, expected 1

        let channelCount = Int(packet[cursor])
        cursor = packet.index(cursor, offsetBy: 1)

        let preSkip = Int(readUInt16LE(packet, at: cursor))
        cursor = packet.index(cursor, offsetBy: 2)

        let inputSampleRate = readUInt32LE(packet, at: cursor)
        cursor = packet.index(cursor, offsetBy: 4)

        let outputGainRaw = readUInt16LE(packet, at: cursor)
        let outputGain = Int16(bitPattern: outputGainRaw)

        return Header(
            channelCount: channelCount,
            preSkip: preSkip,
            inputSampleRate: inputSampleRate,
            outputGainQ78: outputGain
        )
    }
}
