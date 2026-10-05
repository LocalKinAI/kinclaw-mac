import AVFoundation
import Foundation

/// The companion's mini-turns: whether you are done, and when a listener
/// would say 嗯 or nod.
///
/// Tavus's Griffin (2026-10-01) decides every few hundred milliseconds whether
/// to stay quiet, nod, back-channel or take the turn, and in their study half
/// the people who talked to it for a minute took it for a person. The voice
/// loop here decided once: half a second of quiet ended your turn, so a pause
/// to find a word was answered, and while you talked she did nothing at all.
///
/// Two small open models on the box (kin-turn, ~/kin-avatar/turn/server.py)
/// take that part. While the microphone is open its sound streams there, and
///   - ten times a second MaAI's back-channel model (Kyoto University, trained
///     on Chinese conversation) says how likely a listener is to say 嗯 now;
///   - at a pause, Smart Turn v3.2 (pipecat) judges from the last 8 s whether
///     the sentence is finished — in about 7 ms, so asking costs nothing.
/// Asked at 「累了吧，」 it answers 0.01 and she waits; at the full stop, 0.93.
///
/// Off without the box, and when Settings → Voice turns it off; the loop then
/// works exactly as before.
@MainActor
final class TurnTaker: ObservableObject {
    static let shared = TurnTaker()
    static let enabledKey = "kinclaw.companion.miniTurns"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Connected to kin-turn and streaming.
    @Published private(set) var connected = false
    /// Why it is not, in words — shown in Settings → Voice.
    @Published private(set) var problem: String?
    /// The latest back-channel probability, 0…1.
    @Published private(set) var backchannel: Double = 0

    /// A listener would answer now: true to say it (嗯), false to only nod.
    var onBackchannel: ((Bool) -> Void)?

    private var socket: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private var tapped = false
    private var converter: AVAudioConverter?
    private let wanted = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var waiting: [Int: CheckedContinuation<Double?, Never>] = [:]
    private var nextID = 1

    // When to answer. Rare on purpose: the study that put MaAI's timings on an
    // avatar found attention and presence rose with back-channels and fell
    // again when there were too many of them.
    private static let line = 0.55
    private var talkingSince: Date?
    private var lastAnswer = Date.distantPast
    private var lastP = 0.0
    private var answers = 0

    private init() {}

    /// ws://<box>:8104/listen — the box is the machine the video server runs on.
    static var address: URL? {
        guard var parts = URLComponents(string: DiffuserClient.videoHost), parts.host != nil else { return nil }
        parts.scheme = "ws"
        parts.port = 8104
        parts.path = "/listen"
        return parts.url
    }

    // MARK: - Listening

    /// Open the connection and start sending the microphone. Called when the
    /// microphone opens for the user's turn; a no-op when off or already on.
    func listen() {
        guard Self.enabled, socket == nil, let url = Self.address else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task)
        startMicrophone()
    }

    /// Stop sending. The connection closes too: a conversation is turns of
    /// your speech, and kin-turn keeps its model's context between them.
    func pause() {
        stopMicrophone()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        connected = false
        talkingSince = nil
        lastP = 0
        for (_, waiter) in waiting { waiter.resume(returning: nil) }
        waiting.removeAll()
    }

    /// Whether the user is talking in this recording — from the recorder's
    /// own speech detection, which is calibrated to the room.
    func userTalking(_ on: Bool) {
        if on, talkingSince == nil { talkingSince = Date() }
        if !on { talkingSince = nil }
    }

    /// P(the user has finished), judged on the last 8 seconds. Nil when it
    /// cannot say within 400 ms — the caller then does what it always did.
    func isComplete() async -> Double? {
        guard let socket, connected else { return nil }
        let id = nextID
        nextID += 1
        let message = "{\"type\":\"turn\",\"id\":\(id)}"
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            waiting[id] = continuation
            socket.send(.string(message)) { _ in }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let late = self.waiting.removeValue(forKey: id) { late.resume(returning: nil) }
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .failure(let error):
                    self.problem = BoxServices.localNetworkBlocked(error)
                        ? BoxServices.blockedAdvice
                        : "连不上盒子上的 kin-turn（\(Self.address?.absoluteString ?? "")）：Settings → Backend → 盒子上的服务 里开「陪伴小回合」"
                    self.pause()
                case .success(let message):
                    if !self.connected { self.connected = true; self.problem = nil }
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: task)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "bc":
            let p = (object["p"] as? Double) ?? 0
            backchannel = p
            consider(p)
        case "turn":
            if let id = object["id"] as? Int, let waiter = waiting.removeValue(forKey: id) {
                waiter.resume(returning: object["p"] as? Double)
            }
        default:
            break
        }
    }

    /// Answer on the way up through the line, after a second and a half of
    /// talk, four seconds since the last answer at the least — and only every
    /// other one out loud; the rest are a nod.
    private func consider(_ p: Double) {
        defer { lastP = p }
        guard let since = talkingSince, lastP < Self.line, p >= Self.line else { return }
        let now = Date()
        guard now.timeIntervalSince(since) > 1.5, now.timeIntervalSince(lastAnswer) > 4 else { return }
        lastAnswer = now
        answers += 1
        onBackchannel?(answers % 2 == 1)
    }

    // MARK: - Her 嗯

    private var clips: [Data] = []
    private var clipsVoice: String?
    private var player: AVAudioPlayer?

    /// Make the short answers once, in the voice replies are spoken in — again
    /// only when that voice changes.
    func prepareAnswers(with speaker: SpeechSynthesizer, hostname: String) {
        let voice = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        guard clipsVoice != voice || clips.isEmpty else { return }
        clipsVoice = voice
        clips = []
        Task { @MainActor in
            var made: [Data] = []
            for line in ["嗯。", "嗯嗯。", "对。"] {
                if let data = await speaker.clip(line, hostname: hostname) { made.append(data) }
            }
            if self.clipsVoice == voice { self.clips = made }
        }
    }

    /// Say one of them, quieter than a reply. The clip and how long it lasts,
    /// or nil when there are none yet.
    func sayAnswer() -> (data: Data, seconds: TimeInterval)? {
        guard let data = clips.randomElement(), let player = try? AVAudioPlayer(data: data) else { return nil }
        player.volume = 0.6
        player.play()
        self.player = player
        return (data, player.duration)
    }

    // MARK: - The microphone, as 16 kHz mono 16-bit

    private func startMicrophone() {
        guard !tapped else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: wanted) else {
            problem = "麦克风打不开"
            return
        }
        self.converter = converter
        let wanted = self.wanted
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let data = Self.convert(buffer, with: converter, to: wanted) else { return }
            Task { @MainActor in self?.send(data) }
        }
        tapped = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapped = false
            problem = "麦克风打不开：\(error.localizedDescription)"
        }
    }

    private func stopMicrophone() {
        guard tapped else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapped = false
        if engine.isRunning { engine.stop() }
    }

    private func send(_ pcm: Data) {
        guard let socket else { return }
        var frame = Data([1])  // channel 1: the user's microphone
        frame.append(pcm)
        socket.send(.data(frame)) { _ in }
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> Data? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(out.frameLength) * 2)
    }
}
