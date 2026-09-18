import Foundation

/// Makes a new real-person look out of a video.
///
/// This is the wardrobe for the companion who is a person rather than a 3D
/// model. A DH_live look is a folder holding `01.mp4` and
/// `combined_data.json.gz`, built from one video of someone talking — no
/// training, two scripts, a few minutes. So "change her clothes" here means a
/// video of that person in those clothes, and "be someone else" means a video
/// of someone else.
///
/// The scripts belong to the avatar service next door (`localkin-service-avatar`,
/// DH_live mini) and run in its own virtualenv. Running somebody's Python from a
/// GUI app is the kind of thing that fails silently, so every step's output is
/// kept and the last line of it is what the menu shows.
@MainActor
final class RealLookMaker: ObservableObject {
    static let shared = RealLookMaker()

    @Published private(set) var busy = false
    /// What is happening, or what went wrong — shown in the companion's menu.
    @Published private(set) var note: String?
    /// The look that was just built, for the caller to switch to.
    @Published private(set) var made: AvatarStage.Character?

    /// The interpreter to use: the avatar service's own venv if it has one,
    /// else whatever python3 is on PATH. Its requirements (mediapipe, torch)
    /// are not ones to assume of the system one.
    nonisolated static func python(in repo: URL) -> String {
        let venv = repo.appendingPathComponent(".venv/bin/python3")
        if FileManager.default.isExecutableFile(atPath: venv.path) { return venv.path }
        for candidate in ["/opt/homebrew/bin/python3", "/usr/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/bin/python3"
    }

    /// The avatar service's checkout — the same one AvatarStage draws the
    /// shipped looks from, one level up from its web assets.
    static var repo: URL? {
        AvatarStage.source?.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// PATH for the scripts. A GUI app inherits launchd's, which has no
    /// Homebrew in it — the same hole the Term tab fell down with `env: node`,
    /// and here it would be `ffmpeg: not found` inside somebody's Python.
    nonisolated static var searchPath: String {
        AgentLauncher.childPath(for: "/opt/homebrew/bin/ffmpeg")
    }

    /// Whether ffmpeg can run at all, as a sentence to show, or nil when it is
    /// fine. It is not enough that the file exists: a Homebrew ffmpeg keeps
    /// working until one of its libraries is upgraded out from under it.
    nonisolated static func ffmpegTrouble() -> String? {
        let places = searchPath.split(separator: ":").map(String.init)
        guard let binary = places.map({ $0 + "/ffmpeg" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "做形象需要 ffmpeg，这台机器上没有：brew install ffmpeg"
        }
        let check = shell(binary, ["-version"], cwd: URL(fileURLWithPath: "/tmp"))
        if check.code != 0 {
            let why = tail(check.output)
            return "ffmpeg 装了但跑不起来（\(why)）——brew reinstall ffmpeg 之后再来"
        }
        return nil
    }

    /// Build a look named `name` from `video`. Returns immediately; watch
    /// `busy` and `note`.
    func make(from video: URL, name rawName: String) {
        guard !busy else { return }
        guard let repo = Self.repo else {
            note = "找不到数字人服务（localkin-service-avatar），没法做新形象"
            return
        }
        // The first step shells out to ffmpeg for the frames, and a broken
        // ffmpeg comes back as a Python traceback about SIGABRT. Asked here
        // instead, so the answer is the one sentence that fixes it. (Measured
        // on this Mac: a Homebrew ffmpeg whose libass had moved on.)
        if let trouble = Self.ffmpegTrouble() {
            note = trouble
            return
        }
        let name = Self.safeName(rawName)
        let root = AvatarStage.madeFolder.appendingPathComponent(name)
        busy = true
        note = "在处理视频…（提关键点，几分钟）"
        made = nil

        Task { @MainActor in
            let result = await Self.run(repo: repo, video: video, root: root)
            busy = false
            switch result {
            case .success(let character):
                made = character
                note = "「\(character.name)」做好了"
            case .failure(let message):
                note = message
            }
        }
    }

    // MARK: - The two scripts

    private enum Outcome {
        case success(AvatarStage.Character)
        case failure(String)
    }

    private nonisolated static func run(repo: URL, video: URL, root: URL) async -> Outcome {
        let fm = FileManager.default
        let data = root.appendingPathComponent("data")
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        let python = python(in: repo)

        // 1. Keypoints and a matted video. --matting removes the background,
        //    which is the difference between a figure standing in the panel and
        //    a rectangle of somebody's living room.
        let step1 = shell(python, ["data_preparation_mini.py", video.path, data.path, "--matting"],
                          cwd: repo)
        guard step1.code == 0 else {
            return .failure("处理视频失败：" + tail(step1.output))
        }
        // 2. The web assets the page actually loads.
        let step2 = shell(python, ["data_preparation_web.py", root.path], cwd: repo)
        guard step2.code == 0 else {
            return .failure("生成网页资源失败：" + tail(step2.output))
        }
        let assets = root.appendingPathComponent("assets")
        guard fm.fileExists(atPath: assets.appendingPathComponent("01.mp4").path),
              fm.fileExists(atPath: assets.appendingPathComponent("combined_data.json.gz").path) else {
            return .failure("脚本跑完了，但没有生成 01.mp4 和 combined_data.json.gz")
        }
        return .success(AvatarStage.Character(assets: assets, name: root.lastPathComponent))
    }

    /// Run one command to completion, keeping its output. Minutes, on a
    /// background thread; the caller is already off the main actor.
    private nonisolated static func shell(_ launch: String, _ args: [String],
                                          cwd: URL) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        process.currentDirectoryURL = cwd
        // The scripts want their own venv's site-packages and nothing of ours.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PATH"] = searchPath
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let out = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self))
    }

    /// The last line worth showing. tqdm writes carriage returns, so the tail
    /// of the output is usually one very long line of progress bars.
    private nonisolated static func tail(_ output: String) -> String {
        let lines = output.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(2).joined(separator: " / ")
    }

    /// A folder name from what the user typed: their name for her, with
    /// anything that would need quoting taken out.
    static func safeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
        if cleaned.isEmpty {
            return "look-" + String(Int(Date().timeIntervalSince1970))
        }
        return String(cleaned.prefix(40))
    }
}
