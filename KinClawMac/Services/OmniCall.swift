import AVFoundation
import CoreImage
import Foundation
import ImageIO

/// The companion's other brain: MiniCPM-o 4.5 on the box, in full duplex.
///
/// The kinclaw agent hears a finished sentence, thinks, and answers. This one
/// is a call: the microphone goes to the box a second at a time and her voice
/// comes back while you are still talking — the model itself decides, each
/// second, whether to keep listening, answer, or stop because you cut in.
/// With 「看着你」 on it also gets a frame a second from the camera. It is the
/// open half of Tavus's Griffin (OpenBMB, Apache-2.0), served by llama.cpp-omni.
///
/// Measured on the box (M3 Ultra, Q8_0): a second of input is handled in
/// 0.11–0.16 s with sound only and 0.24–0.47 s with a camera frame; her first
/// sound comes 0.6–0.9 s after you stop. A call holds 14 GB, 23 GB with the
/// camera. Her voice is the model's own — a reference recording changes what
/// she says, not how she sounds.
///
/// The box's firewall admits nothing to the server from the network, so it is
/// reached the way the Montage board is: an ssh tunnel to its loopback port.
/// No tools: this brain talks; the agent is the one that does things.
@MainActor
final class OmniCall: ObservableObject {
    static let shared = OmniCall()

    /// "agent" (the kinclaw voice loop) or "omni" (this).
    static let brainKey = "kinclaw.companion.brain"
    static let cameraKey = "kinclaw.companion.omni.camera"
    static var chosen: Bool { UserDefaults.standard.string(forKey: brainKey) == "omni" }
    static var cameraWanted: Bool { UserDefaults.standard.bool(forKey: cameraKey) }
    nonisolated static let port = 19080

    enum State: Equatable { case idle, starting(String), live, down(String) }
    @Published private(set) var state: State = .idle
    /// Her voice is playing.
    @Published private(set) var speaking = false
    /// What she is saying, as it comes.
    @Published private(set) var caption = ""
    /// The microphone, 0…1, for the halo.
    @Published private(set) var level: Double = 0
    /// The camera is sending.
    @Published private(set) var seeing = false

    /// Each piece of her voice as a WAV, when it starts playing — for the face.
    var onClip: ((Data) -> Void)?

    var listening: Bool { state == .live && !speaking }
    var problem: String? {
        switch state {
        case .starting(let what): return what
        case .down(let why): return why
        default: return nil
        }
    }

    private var tunnel: Process?
    private var socket: URLSessionWebSocketTask?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let in16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let out24k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var mic: [Float] = []
    private var queued = 0
    private var faceQueue: [Data] = []
    private var lastWasListen = true
    private var camera: OmniCamera?
    private var generation = 0

    private init() {}

    private static var health: URL { URL(string: "http://127.0.0.1:\(port)/health")! }
    private static var backend: URL { URL(string: "ws://127.0.0.1:\(port)/backend")! }

    // MARK: - Starting and stopping

    func start() async {
        if case .live = state { return }
        if case .starting = state { return }
        generation += 1
        let mine = generation
        caption = ""
        guard !BoxServices.ssh.isEmpty else { state = .down("先在 设置 → Backend 里填盒子的 SSH（user@地址）"); return }
        state = .starting("在叫醒盒子上的 MiniCPM-o…")
        let (code, out) = await BoxServices.run(Self.serveCommand)
        guard mine == generation else { return }
        guard code == 0, out.contains("UP") else {
            state = .down(out.contains("NO-OMNI") ? "盒子上没有 ~/kin-avatar/minicpm-o"
                          : "盒子上的 MiniCPM-o 没起来（~/Library/Logs/kinclaw/omni.log）：\(out.suffix(140))")
            return
        }
        startTunnel()
        state = .starting("在接通盒子…")
        var reached = false
        for _ in 0..<24 {
            if await answering() { reached = true; break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard mine == generation else { return }
        guard reached else { state = .down("ssh 隧道没通到盒子的 \(Self.port) 端口"); return }
        state = .starting("她在准备（第一次要十几秒）…")
        let task = URLSession.shared.webSocketTask(with: Self.backend)
        task.maximumMessageSize = 16 << 20
        socket = task
        task.resume()
        receive(on: task)
        send(["type": "session.init",
              "payload": ["mode": "full_duplex", "use_tts": true,
                          "config": ["force_listen_count": 3]]])
    }

    /// End the call. The server stays up on the box for the next one; it is
    /// stopped under Backend → 盒子上的服务, or in the console's 盒子 panel.
    func stop() {
        generation += 1
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        stopAudio()
        camera?.stop()
        camera = nil
        seeing = false
        tunnel?.terminate()
        tunnel = nil
        state = .idle
        caption = ""
    }

    /// Turn the camera on or off during a call.
    func setCamera(_ on: Bool) {
        guard state == .live else { return }
        if on, camera == nil {
            let camera = OmniCamera()
            self.camera = camera
            Task { @MainActor in
                let ok = await camera.start()
                if self.camera === camera { self.seeing = ok }
                if !ok, self.camera === camera {
                    self.camera = nil
                    self.caption = "摄像头打不开：系统设置 → 隐私与安全性 → 摄像头 里给 LocalKin 打开"
                }
            }
        } else if !on {
            camera?.stop()
            camera = nil
            seeing = false
        }
    }

    /// llama.cpp-omni's plain-HTTP build, from its own directory (it finds the
    /// default voice relative to it), with an 8k context — about 75 s of a
    /// call with the camera on before the oldest falls away.
    static let serveCommand = """
        cd ~/kin-avatar/minicpm-o/llama.cpp-omni 2>/dev/null || { echo NO-OMNI; exit 3; }
        curl -sf -m 2 http://127.0.0.1:\(port)/health >/dev/null && { echo UP; exit 0; }
        mkdir -p ~/Library/Logs/kinclaw
        PATH=/opt/homebrew/bin:/usr/local/bin:$PATH nohup ./build-http/bin/llama-omni-server \
          -m ~/kin-avatar/minicpm-o/MiniCPM-o-4_5-gguf/MiniCPM-o-4_5-Q8_0.gguf --port \(port) -ngl 99 -c 8192 \
          >> ~/Library/Logs/kinclaw/omni.log 2>&1 < /dev/null &
        for i in $(seq 1 40); do
          sleep 0.5
          curl -sf -m 1 http://127.0.0.1:\(port)/health >/dev/null && { echo UP; exit 0; }
        done
        echo SLOW; exit 4
        """

    private func answering() async -> Bool {
        var request = URLRequest(url: Self.health)
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func startTunnel() {
        if let tunnel, tunnel.isRunning { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-N", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                             "-o", "ServerAliveInterval=30", "-o", "ConnectTimeout=6",
                             "-L", "127.0.0.1:\(Self.port):127.0.0.1:\(Self.port)", BoxServices.ssh]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tunnel = nil
                if self.state == .live { self.fail("到盒子的隧道断了") }
            }
        }
        do { try process.run(); tunnel = process } catch {
            state = .down("ssh 起不来：\(error.localizedDescription)")
        }
    }

    private func fail(_ why: String) {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        stopAudio()
        camera?.stop()
        camera = nil
        seeing = false
        state = .down(why)
    }

    // MARK: - The conversation

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .failure:
                    self.fail(self.state == .live ? "通话断了" : "盒子上的 MiniCPM-o 正在别的通话里，或者没接住")
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    if self.socket === task { self.receive(on: task) }
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let event = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "session.created":
            do {
                try startAudio()
                state = .live
                if Self.cameraWanted { setCamera(true) }
            } catch {
                fail("麦克风打不开：\(error.localizedDescription)")
            }
        case "response.output.delta":
            switch event["kind"] as? String {
            case "text":
                let piece = (event["text"] as? String) ?? ""
                if lastWasListen { caption = "" }
                lastWasListen = false
                caption += piece
            case "audio":
                if let b64 = event["audio"] as? String, let data = Data(base64Encoded: b64) { play(data) }
            case "listen":
                lastWasListen = true
            default:
                break
            }
        case "session.closed":
            let reason = (event["reason"] as? String) ?? ""
            fail("通话结束了（\(reason)）")
        default:
            break
        }
    }

    private func send(_ object: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        socket.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    // MARK: - Sound in and out

    /// One engine for both directions with voice processing on, which is the
    /// echo canceller: what she says through the speakers is taken back out of
    /// what the microphone hears, so the model does not answer itself.
    ///
    /// On Jacky's Mac mini it will not start (avfaudio -10875, the first call,
    /// 2026-10-02): a USB microphone and the built-in speakers are two devices,
    /// and voice processing could not join them. Then the call goes on without
    /// it, and while she talks through speakers the microphone sends silence —
    /// she cannot hear herself, and you cut in once she pauses (or any time
    /// with headphones, or with Settings → Voice → Talk over it set to Always).
    private func startAudio() throws {
        do {
            try startAudio(voiceProcessing: true)
            echoCancelled = true
        } catch {
            let code = (error as NSError).code
            stopAudio()
            try startAudio(voiceProcessing: false)
            echoCancelled = false
            caption = AudioRoute.bargeInAllowed()
                ? "这台 Mac 开不了回声消除（\(code)），戴着耳机就好"
                : "这台 Mac 开不了回声消除（\(code)）：她说话时先不听你，说完就听；戴耳机可以随时插话"
        }
    }

    /// Without the echo canceller, whether what the microphone hears now is
    /// her, through the speakers.
    private var echoing: Bool {
        !echoCancelled && !AudioRoute.bargeInAllowed() && (speaking || Date() < quietUntil)
    }
    private var echoCancelled = true
    private var quietUntil = Date.distantPast

    private func startAudio(voiceProcessing: Bool) throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let input = engine.inputNode
        if voiceProcessing { try input.setVoiceProcessingEnabled(true) }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: out24k)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: in16k) else {
            throw NSError(domain: "OmniCall", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有能用的麦克风"])
        }
        converter.downmix = true
        let target = in16k
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let samples = Self.convert(buffer, with: converter, to: target) else { return }
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
            Task { @MainActor in self?.heard(samples, rms: rms) }
        }
        engine.prepare()
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
        mic = []
        queued = 0
        faceQueue = []
    }

    private func stopAudio() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            player?.stop()
            engine.stop()
        }
        engine = nil
        player = nil
        queued = 0
        faceQueue = []
        speaking = false
        level = 0
    }

    /// A second at a time, exactly: the model was trained on one-second steps
    /// and the server takes one step per message.
    private func heard(_ samples: [Float], rms: Float) {
        level = level * 0.6 + Double(min(1, rms * 12)) * 0.4
        mic.append(contentsOf: echoing ? [Float](repeating: 0, count: samples.count) : samples)
        while mic.count >= 16_000 {
            let second = Array(mic.prefix(16_000))
            mic.removeFirst(16_000)
            var input: [String: Any] = ["audio": second.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()]
            if let frame = camera?.latest { input["video_frames"] = [frame.base64EncodedString()] }
            send(["type": "input.append", "input": input])
        }
    }

    /// Her voice: float32 24 kHz, about a second a piece, in the order it came.
    /// The first piece after a silence waits 200 ms so the next can arrive in time.
    private func play(_ f32: Data) {
        guard let player, let engine, engine.isRunning else { return }
        let count = f32.count / 4
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: out24k, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        f32.withUnsafeBytes { raw in
            if let base = raw.bindMemory(to: Float.self).baseAddress {
                buffer.floatChannelData![0].update(from: base, count: count)
            }
        }
        let wav = Self.wav(f32, rate: 24_000)
        let first = queued == 0
        queued += 1
        speaking = true
        var when: AVAudioTime?
        if first {
            when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.2))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onClip?(wav) }
        } else {
            faceQueue.append(wav)
        }
        let gen = generation
        player.scheduleBuffer(buffer, at: when, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.queued = max(0, self.queued - 1)
                if !self.faceQueue.isEmpty { self.onClip?(self.faceQueue.removeFirst()) }
                if self.queued == 0 {
                    self.speaking = false
                    // The room rings on a moment after the speakers stop.
                    self.quietUntil = Date().addingTimeInterval(0.4)
                }
            }
        }
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }

    /// A 16-bit mono WAV of float samples, for the face's lip-sync.
    nonisolated private static func wav(_ f32: Data, rate: Int) -> Data {
        let samples = f32.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * 32767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1)
        put32(UInt32(rate)); put32(UInt32(rate * 2)); put16(2); put16(16)
        header.append(contentsOf: Array("data".utf8)); put32(UInt32(pcm.count))
        return header + pcm
    }
}

/// One frame a second from the camera, as a JPEG 448 pixels wide — what the
/// model looks at (64 vision tokens a frame).
final class OmniCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kinclaw.omni.camera")
    private let context = CIContext()
    private let lock = NSLock()
    private var jpeg: Data?
    private var lastAt = Date.distantPast

    var latest: Data? { lock.lock(); defer { lock.unlock() }; return jpeg }

    func start() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted, let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        queue.async { self.session.startRunning() }
        return true
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastAt) > 0.9, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAt = Date()
        var image = CIImage(cvPixelBuffer: pixels)
        let scale = 448 / max(1, image.extent.width)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(of: image, colorSpace: space,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
        else { return }
        lock.lock(); jpeg = data; lock.unlock()
    }
}
