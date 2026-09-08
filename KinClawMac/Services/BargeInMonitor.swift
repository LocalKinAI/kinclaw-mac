import AVFoundation

/// Listens while the agent is talking so you can interrupt it.
///
/// The obvious way to do this — open the recorder during playback and
/// watch its level — hears the speakers and interrupts the agent with
/// its own voice. So this runs the input through `AVAudioEngine` with
/// voice processing enabled, which is macOS's acoustic echo canceller:
/// what comes out of the speakers is subtracted from what comes into
/// the mic, and what is left is the room, which is to say you.
///
/// Even with cancellation the residue is not zero, so a trigger needs
/// speech that is both loud relative to the measured floor and
/// sustained — a door closing or a keyboard clack is one buffer, a
/// person starting a sentence is many.
@MainActor
final class BargeInMonitor: ObservableObject {

    /// Called on the main actor the moment sustained speech is heard.
    var onSpeech: (() -> Void)?

    @Published private(set) var isMonitoring = false
    /// Live level in dBFS, for a UI that wants to show the mic is hot.
    @Published private(set) var level: Float = -60

    private let engine = AVAudioEngine()
    private var installed = false
    private var floorDB: Float = -50
    private var consecutive = 0
    private var buffersSeen = 0

    /// How far above the measured floor a buffer must be to count as
    /// speech, and how many in a row are needed. At ~23ms per buffer,
    /// six buffers is about 140ms — long enough to reject a click,
    /// short enough that interrupting still feels immediate.
    private let marginDB: Float = 12
    private let neededConsecutive = 6
    /// Buffers spent measuring the room before any trigger is allowed.
    /// Without this the first breath after playback starts reads as
    /// speech, because the floor still holds its default.
    private let calibrationBuffers = 12

    func start() {
        guard !isMonitoring else { return }
        consecutive = 0
        buffersSeen = 0
        floorDB = -50

        let input = engine.inputNode
        // Echo cancellation. Without it the agent interrupts itself
        // roughly every sentence.
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            // Older hardware or a device that refuses; monitoring still
            // works, it just needs the user to be louder than the room
            // AND the speakers.
            print("[BargeInMonitor] voice processing unavailable: \(error)")
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        if installed { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let db = Self.peakDB(buffer)
            Task { @MainActor in self.consume(db) }
        }
        installed = true

        do {
            engine.prepare()
            try engine.start()
            isMonitoring = true
        } catch {
            print("[BargeInMonitor] engine failed to start: \(error)")
            input.removeTap(onBus: 0)
            installed = false
        }
    }

    func stop() {
        guard isMonitoring || installed else { return }
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            installed = false
        }
        if engine.isRunning { engine.stop() }
        isMonitoring = false
        level = -60
        consecutive = 0
    }

    /// One buffer's level: update the floor, count sustained speech,
    /// fire once.
    private func consume(_ db: Float) {
        level = db
        buffersSeen += 1

        if db > floorDB + marginDB {
            consecutive += 1
        } else {
            consecutive = 0
            // Track the quiet level so a noisy room raises the bar
            // rather than triggering constantly. Rises slowly, falls
            // fast, so the floor follows a room that gets quieter
            // without being dragged up by the speech it should detect.
            floorDB = db < floorDB ? db : floorDB + (db - floorDB) * 0.05
        }

        guard buffersSeen > calibrationBuffers,
              consecutive >= neededConsecutive else { return }
        consecutive = 0
        let fire = onSpeech
        stop()
        fire?()
    }

    /// Peak sample of a buffer in dBFS. Peak rather than RMS: speech
    /// onset shows up in the peak a buffer or two before it moves the
    /// average, and the whole point here is reacting early.
    private nonisolated static func peakDB(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return -60 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return -60 }
        var peak: Float = 0
        for i in 0..<n {
            let v = abs(data[0][i])
            if v > peak { peak = v }
        }
        return peak > 0 ? max(-60, 20 * log10(peak)) : -60
    }
}
