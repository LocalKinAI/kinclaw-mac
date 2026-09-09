import Foundation

/// Trims the silence Kokoro pads around every clip.
///
/// Measured here: each sentence comes back with ~400ms of silence in
/// front and ~700ms behind, whatever its length. Spoken as one
/// paragraph that is the pause between sentences and it sounds right.
/// Spoken one sentence at a time it is a 1.1s hole between every
/// sentence, on top of the player handoff — most of what made streamed
/// speech sound like someone reading a list. The first clip also
/// started 400ms later than it had to.
///
/// Only 16-bit PCM WAV is handled, which is what Kokoro sends; anything
/// else comes back untouched.
enum WAVTrim {

    /// Keep this much of the silence on either side so the joins still
    /// breathe: a comma's worth in front, a short beat behind.
    static func trim(_ data: Data,
                     leadKeepMs: Int = 60,
                     trailKeepMs: Int = 160,
                     threshold: Float = 0.01) -> Data {
        guard data.count > 44,
              data[data.startIndex..<data.startIndex + 4] == Data("RIFF".utf8),
              data[data.startIndex + 8..<data.startIndex + 12] == Data("WAVE".utf8)
        else { return data }

        // Walk the chunks: we need "fmt " to know the layout and "data"
        // to know where the samples are.
        var pos = 12
        var format = 0, channels = 0, sampleRate = 0, bits = 0
        var dataStart = -1, dataLen = 0
        while pos + 8 <= data.count {
            let id = String(decoding: data[data.startIndex + pos..<data.startIndex + pos + 4], as: UTF8.self)
            let size = Int(le32(data, pos + 4))
            let body = pos + 8
            if id == "fmt ", body + 16 <= data.count {
                format = Int(le16(data, body))
                channels = Int(le16(data, body + 2))
                sampleRate = Int(le32(data, body + 4))
                bits = Int(le16(data, body + 14))
            } else if id == "data" {
                dataStart = body
                dataLen = min(size, data.count - body)
                break
            }
            pos = body + size + (size & 1)
        }
        guard format == 1, bits == 16, channels >= 1, sampleRate > 0,
              dataStart > 0, dataLen > 0 else { return data }

        let frameBytes = 2 * channels
        let frames = dataLen / frameBytes
        guard frames > 0 else { return data }
        let thr = Int16(threshold * 32767)

        // First and last frames with any channel above the threshold.
        // Scanned from each end so a long clip costs two short walks,
        // not one full pass.
        var first = -1
        var last = -1
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: data.startIndex + dataStart)
            func loud(_ f: Int) -> Bool {
                for c in 0..<channels {
                    let v = base.loadUnaligned(fromByteOffset: (f * channels + c) * 2, as: Int16.self)
                    if v > thr || v < -thr { return true }
                }
                return false
            }
            for f in 0..<frames where loud(f) { first = f; break }
            if first >= 0 {
                for f in stride(from: frames - 1, through: first, by: -1) where loud(f) { last = f; break }
            }
        }
        // Silence end to end: not ours to judge, play it as sent.
        guard first >= 0, last >= first else { return data }

        let start = max(0, first - sampleRate * leadKeepMs / 1000)
        let end = min(frames, last + 1 + sampleRate * trailKeepMs / 1000)
        guard start > 0 || end < frames else { return data }

        let newLen = (end - start) * frameBytes
        var out = Data(capacity: dataStart + newLen)
        out.append(data[data.startIndex..<data.startIndex + dataStart])
        out.append(data[data.startIndex + dataStart + start * frameBytes
                        ..< data.startIndex + dataStart + end * frameBytes])
        // The two sizes that changed: the RIFF payload and the data chunk.
        put32(&out, 4, UInt32(out.count - 8))
        put32(&out, dataStart - 4, UInt32(newLen))
        return out
    }

    private static func le16(_ d: Data, _ at: Int) -> UInt16 {
        d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: d.startIndex + at, as: UInt16.self) }.littleEndian
    }

    private static func le32(_ d: Data, _ at: Int) -> UInt32 {
        d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: d.startIndex + at, as: UInt32.self) }.littleEndian
    }

    private static func put32(_ d: inout Data, _ at: Int, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.replaceSubrange(at..<at + 4, with: $0) }
    }
}
