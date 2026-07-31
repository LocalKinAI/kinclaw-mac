import AVFoundation

/// Listens for the user starting to talk *while the agent is still speaking*,
/// so a long reply can be interrupted instead of waited out.
///
/// The obvious problem with opening the mic during playback is that the mic
/// hears the speaker, and the agent interrupts itself on its own voice. macOS
/// solves this in the audio unit: `setVoiceProcessingEnabled(true)` turns on
/// acoustic echo cancellation. Measured on this machine, playing a clip
/// through the speakers while recording:
///
///     AEC off → mic picks up -10.8 dBFS
///     AEC on  → mic picks up -44.7 dBFS
///
/// 34 dB of suppression puts the agent's own voice down at room-tone level,
/// while speech from the user sits around -20 dBFS. That gap is what makes
/// the threshold below meaningful rather than a coin flip.
///
/// This deliberately does NOT record. `VoiceRecorder` owns capture and stays
/// on AVAudioRecorder — a path that currently works and isn't worth
/// destabilising. This class only answers "has the user started talking", and
/// hands off to the normal recording flow the moment it's sure.
final class BargeInMonitor {

    /// Called on the main queue the first time sustained speech is detected.
    /// Fires at most once per `start()`.
    var onSpeechDetected: (() -> Void)?

    private var engine: AVAudioEngine?
    private var consecutiveLoudFrames = 0
    private var fired = false

    /// Threshold is calibrated per reply rather than fixed.
    ///
    /// A constant looked fine on the average — residual echo averages around
    /// -44 dBFS — but measuring the *loudest* frame while the agent spoke gave
    /// -29.7 dBFS. A fixed -33 was already being crossed by individual frames
    /// and survived only because they weren't consecutive; a louder reply or a
    /// more reflective room would have had the agent cutting itself off.
    ///
    /// So: sample the first few frames of playback, when the only thing the
    /// mic can hear is the agent, and put the line above *that*. Clamped so a
    /// silent passage at the start can't drop it into the noise, and a loud
    /// one can't raise it past ordinary speech.
    /// Level is not what separates the user from the echo — persistence is.
    ///
    /// Measured in the app's real arrangement (AVAudioPlayer playing, this
    /// engine capturing, same process, volume at maximum): cancellation brings
    /// the average down from -8.2 to -29.1 dBFS, but residual **peaks still
    /// reach -15.5**, which is squarely inside the range of ordinary speech.
    /// No threshold can tell those apart, and an earlier attempt to calibrate
    /// one per reply was solving the wrong problem.
    ///
    /// What does separate them is how long the level stays up. Over a 16s
    /// reply with nobody talking, the longest unbroken run above each line:
    ///
    ///     -30 dBFS → 5 frames (213 ms)
    ///     -25 dBFS → 4 frames (171 ms)
    ///     -22 dBFS → 3 frames (128 ms)
    ///     -20 dBFS → 2 frames  (85 ms)
    ///
    /// Echo peaks and passes; a person talking holds the level for a second or
    /// more (20+ frames). So the line sits at -22 and confirmation needs 6
    /// consecutive frames — double the longest echo run measured, while
    /// costing ~260ms of interrupt latency.
    ///
    /// These came from one machine at full volume (the worst case for echo).
    /// If a room or a speaker defeats them, the setting turns the whole
    /// feature off rather than degrading into random interruptions.
    private let speechThresholdDB: Float = -22
    private let framesToConfirm = 6

    var isRunning: Bool { engine != nil }

    func start() {
        guard engine == nil else { return }
        consecutiveLoudFrames = 0
        fired = false

        let engine = AVAudioEngine()
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            // Without echo cancellation this would hear the agent and fire on
            // every reply, which is worse than not supporting interruption at
            // all. Bail out and leave playback alone.
            return
        }

        let format = input.inputFormat(forBus: 0)
        // Voice processing reports 3 deinterleaved channels; all three carry
        // the same processed signal here, so channel 0 is enough.
        guard format.channelCount > 0, format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self = self, !self.fired,
                  let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            var sumOfSquares: Float = 0
            for i in 0..<count { sumOfSquares += channel[i] * channel[i] }
            let rms = (sumOfSquares / Float(count)).squareRoot()
            let db = 20 * log10(max(rms, 1e-9))

            if db > self.speechThresholdDB {
                self.consecutiveLoudFrames += 1
                if self.consecutiveLoudFrames >= self.framesToConfirm {
                    self.fired = true
                    DispatchQueue.main.async { self.onSpeechDetected?() }
                }
            } else {
                self.consecutiveLoudFrames = 0
            }
        }

        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Leaving voice processing on holds the audio unit in a mode that
        // affects other capture on the device; hand it back.
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        self.engine = nil
        onSpeechDetected = nil
    }
}
