import Foundation

/// Mouth shapes, read off the audio that is about to be played.
///
/// The stage used to open one mouth shape — `aa` — in proportion to the
/// microphone's level, which is a mouth flapping rather than a mouth
/// speaking: every sentence looks the same, and the shape never matches the
/// sound. A VRM face has five, and Kokoro hands us the whole clip before it
/// plays, so the shapes can be worked out once and played back in step.
///
/// The method is formant bands, not phonemes. Three probes — 350–700 Hz where
/// an open vowel puts its first formant, 800–1400 for a rounded one, and
/// 1900–3000 where a spread vowel puts its second — and the one that stands
/// out **against its own average across the clip** decides the shape. The
/// averaging matters: speech has far more energy low down than high up, so
/// comparing the bands directly picks the low one nearly every time. Measured
/// on a 4.5s Kokoro line (225 frames):
///
///                     absolute        against its own average
///     aa               55.6%          28.0%
///     oh                4.0%          12.0%
///     ee                1.3%          12.0%
///     ou                3.6%           8.4%
///     ih                4.0%           8.0%
///     closed           31.6%          31.6%
///
/// The second column is a mouth that moves the way a mouth moves. This is
/// still an estimate — a real phoneme timing from the synthesiser would beat
/// it — but it is an estimate of the right thing, and it costs one pass over
/// a clip we already have in memory.
struct VisemeTrack {
    struct Frame {
        let at: TimeInterval
        let viseme: String      // aa · ih · ou · ee · oh · "" for closed
        let weight: Double      // 0…1, how far open
    }

    let frames: [Frame]
    let duration: TimeInterval

    /// 20ms per frame: fast enough that a consonant does not smear a vowel,
    /// slow enough that the face is not asked to change 100 times a second.
    static let hop: TimeInterval = 0.02
    private static let window: TimeInterval = 0.04
    /// Below this the mouth is closed. Kokoro pads its clips with silence.
    private static let silence = 0.02

    /// Read a 16-bit PCM WAV — what Kokoro returns — and work out the shapes.
    /// Returns nil for anything that is not that, rather than guessing.
    init?(wav: Data) {
        guard let audio = PCM(wav: wav), !audio.samples.isEmpty else { return nil }
        let rate = Double(audio.rate)
        let hopCount = max(1, Int(rate * Self.hop))
        let winCount = max(hopCount, Int(rate * Self.window))
        let x = audio.samples

        // Pass one: level and the three band magnitudes per frame.
        var rows: [(rms: Double, bands: [Double])] = []
        var start = 0
        while start + winCount <= x.count {
            let frame = Array(x[start..<(start + winCount)])
            let rms = (frame.reduce(0) { $0 + $1 * $1 } / Double(frame.count)).squareRoot()
            rows.append((rms, [Self.band(frame, 350, 700, rate),
                               Self.band(frame, 800, 1400, rate),
                               Self.band(frame, 1900, 3000, rate)]))
            start += hopCount
        }
        guard !rows.isEmpty else { return nil }

        // Pass two: each band's own average over the frames that have sound,
        // so the classification is about shape rather than loudness.
        let voiced = rows.filter { $0.rms >= Self.silence }
        let reference: [Double] = (0..<3).map { i in
            guard !voiced.isEmpty else { return 0 }
            return voiced.reduce(0) { $0 + log($1.bands[i] + 1e-9) } / Double(voiced.count)
        }

        frames = rows.enumerated().map { index, row in
            let at = Double(index) * Self.hop
            guard row.rms >= Self.silence else { return Frame(at: at, viseme: "", weight: 0) }
            let deviation = (0..<3).map { log(row.bands[$0] + 1e-9) - reference[$0] }
            let open = min(1, row.rms * 6)
            let top = deviation.firstIndex(of: deviation.max()!) ?? 0
            let shape: String
            switch top {
            case 0:  shape = open > 0.35 ? "aa" : "ou"
            case 1:  shape = open > 0.5 ? "oh" : "ou"
            default: shape = open > 0.45 ? "ee" : "ih"
            }
            return Frame(at: at, viseme: shape, weight: open)
        }
        duration = Double(rows.count) * Self.hop
    }

    /// The shape at a moment, for a player stepping through in real time.
    func frame(at time: TimeInterval) -> Frame? {
        guard !frames.isEmpty else { return nil }
        let index = Int(time / Self.hop)
        guard index >= 0, index < frames.count else { return nil }
        return frames[index]
    }

    // MARK: - The maths

    /// Magnitude around a band, at three probe frequencies.
    ///
    /// A Goertzel rather than an FFT: three numbers are wanted, not 512, and
    /// this is a dozen lines with no dependency and no padding.
    private static func band(_ frame: [Double], _ lo: Double, _ hi: Double,
                             _ rate: Double) -> Double {
        var total = 0.0
        for f in [lo, (lo + hi) / 2, hi] {
            let w = 2 * Double.pi * f / rate
            var cosine = 0.0, sine = 0.0
            for (i, v) in frame.enumerated() {
                cosine += v * cos(w * Double(i))
                sine += v * sin(w * Double(i))
            }
            total += (cosine * cosine + sine * sine).squareRoot() / Double(frame.count)
        }
        return total / 3
    }

    /// The samples out of a WAV, mono, -1…1.
    struct PCM {
        let samples: [Double]
        let rate: Int

        init?(wav: Data) {
            guard wav.count > 44,
                  wav[0...3].elementsEqual("RIFF".utf8),
                  wav[8...11].elementsEqual("WAVE".utf8) else { return nil }
            var cursor = 12
            var rate = 0, channels = 1, bits = 16
            var data: Data?
            while cursor + 8 <= wav.count {
                let id = wav[cursor..<(cursor + 4)]
                let size = Int(wav.u32(at: cursor + 4))
                let body = cursor + 8
                guard body + size <= wav.count || id.elementsEqual("data".utf8) else { break }
                if id.elementsEqual("fmt ".utf8), size >= 16 {
                    channels = Int(wav.u16(at: body + 2))
                    rate = Int(wav.u32(at: body + 4))
                    bits = Int(wav.u16(at: body + 14))
                } else if id.elementsEqual("data".utf8) {
                    let end = min(wav.count, body + (size > 0 ? size : wav.count - body))
                    data = wav[body..<end]
                }
                cursor = body + size + (size % 2)
            }
            guard let payload = data, rate > 0, bits == 16, channels >= 1 else { return nil }
            // Mono by taking the first channel: the mouth does not care which.
            let count = payload.count / 2
            var out = [Double](); out.reserveCapacity(count / channels)
            var index = 0
            while index + channels <= count {
                let sample = Int16(bitPattern: payload.u16(at: payload.startIndex + index * 2))
                out.append(Double(sample) / 32768)
                index += channels
            }
            self.samples = out
            self.rate = rate
        }
    }
}

private extension Data {
    func u16(at index: Int) -> UInt16 {
        let i = index < startIndex ? startIndex + index : index
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }
    func u32(at index: Int) -> UInt32 {
        let i = index < startIndex ? startIndex + index : index
        return UInt32(self[i]) | (UInt32(self[i + 1]) << 8)
             | (UInt32(self[i + 2]) << 16) | (UInt32(self[i + 3]) << 24)
    }
}
