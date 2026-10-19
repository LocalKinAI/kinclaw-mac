import AVFoundation
import Foundation
import ImageIO
import os

/// Her face from the box, lip-synced to her voice as she speaks — 「接进陪伴吧」
/// (2026-10-02), after Jacky had seen it: 「不飘了」.
///
/// kin-face on the box (~/kin-avatar/face/server.py, :8105) streams her twenty
/// frames a second: a body rendered once by Ditto from her photograph (two of
/// them — one that listens, one whose head moves as she talks; the camera
/// still), and a mouth drawn by QuickTalk from each sentence of her voice
/// (MuseTalk until 2026-10-18 — 「好太多了」). A whole sentence is pushed the
/// moment its turn comes; its first frame is ready 0.13 s later and each frame
/// leaves the box at its own time, `latency_s` after the push, so the speaker
/// plays every clip `voiceDelay` later than it hands it over and the lips meet
/// the sound.
///
/// Frames are shown at the pace the box sent them, not as they come in: this
/// Mac and the box are both on Wi-Fi, which held frames back 0.4 s and more
/// (2026-10-02; on the box itself they leave 50 ms apart, never more than 62)
/// — her face stood still, then jumped ahead, while her voice went on. Each
/// frame carries its slot on the box's clock and is shown `buffer` after the
/// soonest any frame has come lately; her voice waits as much longer. The
/// buffer follows the link (95 % of frames on time over ten seconds, 0.08 to
/// 0.5 s) and is retuned only while she is quiet. Every frame is answered
/// ("seen"), and the box drops frames rather than queue them behind a full
/// link: when the Wi-Fi fell to 5 Mbit/s for a while (twenty 154 KB frames a
/// second are 25), frames it had queued arrived up to 16 s late.
///
/// Why not the whole face from her voice (Ditto alone): it is 91 ms a frame on
/// the box's GPU at its best, ten frames a second. H3 and LTX are a hundred
/// times slower than speech. Those make the body; QuickTalk the mouth.
@MainActor
final class LiveFace: ObservableObject {
    static let shared = LiveFace()
    static let enabledKey = "kinclaw.companion.liveFace"
    static var chosen: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static let port = 8105

    /// The latest frame, for the view.
    @Published private(set) var frame: CGImage?
    @Published private(set) var connected = false
    @Published private(set) var problem: String?
    /// Frames made from her voice are showing (as opposed to her idling).
    @Published private(set) var talking = false

    /// How much later each clip plays than it is pushed: the box's latency and
    /// the buffer. Read by the speaker on whatever thread schedules the clip.
    nonisolated static var voiceDelay: TimeInterval { delay.withLock { $0 } }
    private nonisolated static let delay = OSAllocatedUnfairLock<TimeInterval>(initialState: 0.5)

    /// From the sound pushed to its frames leaving the box; the server says.
    private(set) var latency: TimeInterval = 0.35 { didSet { publishDelay() } }
    /// How far behind the soonest arrival frames are shown.
    private(set) var buffer: TimeInterval = 0.15 { didSet { publishDelay() } }

    private var socket: URLSessionWebSocketTask?
    private let decoder = DispatchQueue(label: "kinclaw.liveface.decode")
    /// Attached to the companion: a dropped connection (the box service
    /// restarted, a new look) is tried again every few seconds.
    private var wanted = false

    private struct Pending {
        let due: TimeInterval
        let image: CGImage
        let kind: UInt8
    }
    private var pending: [Pending] = []
    /// Arrival minus slot for the last ten seconds of frames (local uptime
    /// against the box's clock: only the differences mean anything).
    private var lateness: [(at: TimeInterval, delay: TimeInterval)] = []
    private var lastTalk: TimeInterval = 0
    private var shower: Timer?

    private init() {}

    static var address: URL? {
        guard var parts = URLComponents(string: DiffuserClient.videoHost), parts.host != nil else { return nil }
        parts.scheme = "ws"
        parts.port = port
        parts.path = "/face"
        parts.queryItems = [URLQueryItem(name: "v", value: "2")]  // frames carry their slot
        return parts.url
    }

    // MARK: - Connection

    func connect() {
        wanted = true
        guard socket == nil, let url = Self.address else { return }
        problem = nil
        pending.removeAll()
        lateness.removeAll()
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 4 << 20
        socket = task
        task.resume()
        receive(on: task)
        Task { await readLatency() }
    }

    func disconnect() {
        wanted = false
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        stopShowing()
        connected = false
        talking = false
    }

    private func publishDelay() {
        let seconds = latency + buffer
        Self.delay.withLock { $0 = seconds }
    }

    private func readLatency() async {
        guard var parts = Self.address.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return }
        parts.scheme = "http"
        parts.path = "/health"
        parts.queryItems = nil
        guard let url = parts.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seconds = object["latency_s"] as? Double else { return }
        latency = seconds
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    guard let self, self.socket === task else { return }
                    self.socket = nil
                    self.stopShowing()
                    self.connected = false
                    self.problem = BoxServices.localNetworkBlocked(error)
                        ? BoxServices.blockedAdvice
                        : "连不上盒子上的实时口型（kin-face :\(Self.port)）：设置 → Backend → 盒子上的服务 里开「实时口型」"
                    if self.wanted {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                            guard let self, self.wanted, self.socket == nil else { return }
                            self.connect()
                        }
                    }
                }
            case .success(let message):
                if case .data(let data) = message, data.count > 17 {
                    let time = ProcessInfo.processInfo.systemUptime
                    let start = data.startIndex
                    let kind = data[start]
                    // A box from before the slots sends the JPEG (FF D8) right after the first double.
                    let slotted = !(data[start + 9] == 0xFF && data[start + 10] == 0xD8)
                    let slot: Double? = slotted
                        ? data.subdata(in: (start + 9)..<(start + 17)).withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
                        : nil
                    let jpeg = data.subdata(in: (start + (slotted ? 17 : 9))..<data.endIndex)
                    if let slot {
                        // Arrived: the box sends no more than the link carries (it drops
                        // frames that would have queued behind a full one).
                        task.send(.string("{\"type\":\"seen\",\"slot\":\(slot)}")) { _ in }
                    }
                    self?.decoder.async {
                        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                        Task { @MainActor [weak self] in
                            guard let self, self.socket === task else { return }
                            self.arrived(image, kind: kind, slot: slot, at: time)
                        }
                    }
                }
                Task { @MainActor in
                    guard let self, self.socket === task else { return }
                    self.receive(on: task)
                }
            }
        }
    }

    // MARK: - Pacing

    private func arrived(_ image: CGImage, kind: UInt8, slot: Double?, at time: TimeInterval) {
        connected = true
        if kind == 2 { lastTalk = time }
        guard let slot else {  // an older box: shown as it comes
            show(image, kind: kind)
            return
        }
        let delay = time - slot
        lateness.append((time, delay))
        if let oldest = lateness.first, time - oldest.at > 10 {
            lateness.removeAll { time - $0.at > 10 }
        }
        let soonest = lateness.lazy.map(\.delay).min() ?? delay
        // Retuned only while she is quiet, so no sentence is shown at two paces.
        if time - lastTalk > 1.5, lateness.count >= 60 {
            let late = lateness.map { $0.delay - soonest }.sorted()
            buffer = min(0.5, max(0.08, late[late.count * 95 / 100] + 0.03))
        }
        pending.append(Pending(due: slot + soonest + buffer, image: image, kind: kind))
        if shower == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.showDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            shower = timer
        }
    }

    /// The newest frame whose time has come; any older ones still waiting are
    /// passed over (they came too late to be shown in turn).
    private func showDue() {
        let now = ProcessInfo.processInfo.systemUptime
        var due: Pending?
        while let first = pending.first, first.due <= now {
            due = first
            pending.removeFirst()
        }
        if let due { show(due.image, kind: due.kind) }
    }

    private func show(_ image: CGImage, kind: UInt8) {
        frame = image
        talking = kind == 2
    }

    private func stopShowing() {
        shower?.invalidate()
        shower = nil
        pending.removeAll()
    }

    // MARK: - Her voice

    /// One clip, whole, the moment its turn comes (the speaker's push timeline).
    func push(_ wav: Data) {
        guard let socket, let pcm = Self.pcm16k(wav) else { return }
        socket.send(.data(pcm)) { _ in }
    }

    /// Nothing more to say for now: the box renders the tail of the last clip.
    func end() { send(["type": "end"]) }

    /// She was cut off.
    func interrupt() { send(["type": "interrupt"]) }

    private func send(_ object: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        socket.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    /// A WAV as 16-bit mono 16 kHz samples.
    nonisolated static func pcm16k(_ wav: Data) -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-face-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? wav.write(to: file)) != nil,
              let audio = try? AVAudioFile(forReading: file),
              let input = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
              (try? audio.read(into: input)) != nil,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: audio.processingFormat, to: target) else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / audio.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let samples = output.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(output.frameLength) * 2)
    }
}
