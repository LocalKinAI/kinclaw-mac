import Foundation

/// Each Studio agent's notebook: CLAUDE.md in its own folder, which Claude
/// Code reads when it starts (and AGENTS.md beside it, the same file, which
/// Codex reads). The agent keeps it with the studio_note tool — what it
/// learned, what the person likes, and the problems it finds in the studio,
/// written for whoever develops the studio to read and fix ("这样你能迅速知道
/// 问题，然后修改"). The agent cannot edit files: the app writes each note, dated,
/// into its section, and nowhere else.
@MainActor
enum StudioNotebook {
    enum Kind: String, CaseIterable {
        case lesson, preference, problem

        var heading: String {
            switch self {
            case .lesson: return "## 心得"
            case .preference: return "## 偏好"
            case .problem: return "## 问题（给开发者）"
            }
        }
    }

    static func file(_ place: StudioAgent.Place) -> URL {
        StudioAgent.of(place).folder.appendingPathComponent("CLAUDE.md")
    }

    /// The notebook, made if there is none, with Codex's name for it beside it.
    static func ensure(_ place: StudioAgent.Place) {
        let fm = FileManager.default
        let url = file(place)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            let tab = ["film": "Film（片场）", "motion": "Motion", "comfy": "Comfy", "montage": "Montage（OpenMontage）"][place.rawValue] ?? place.rawValue
            let body = """
                # \(tab) 标签 agent 的工作笔记

                每次开工先读这里。往里记用 studio_note（kind: lesson 心得 / preference 偏好 / problem 问题），不直接改这个文件。
                「问题」一节是写给开发者的，他会读它来修片场：写清楚发生了什么、在哪（片子、镜头、文件）、怎么修会更好。

                \(Kind.lesson.heading)

                \(Kind.preference.heading)

                \(Kind.problem.heading)

                """
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        let codex = url.deletingLastPathComponent().appendingPathComponent("AGENTS.md")
        if (try? fm.destinationOfSymbolicLink(atPath: codex.path)) == nil, !fm.fileExists(atPath: codex.path) {
            try? fm.createSymbolicLink(atPath: codex.path, withDestinationPath: "CLAUDE.md")
        }
    }

    /// One dated line, at the end of its section.
    static func add(_ place: StudioAgent.Place, _ kind: Kind, _ text: String) -> (String, Bool) {
        ensure(place)
        let url = file(place)
        guard var notebook = try? String(contentsOf: url, encoding: .utf8) else { return ("读不了笔记：\(url.path)", true) }
        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm"
        let line = "- \(clock.string(from: Date())) · " + text.replacingOccurrences(of: "\n", with: " ")
        if let heading = notebook.range(of: kind.heading) {
            // After the section's last line: before the next heading, less the
            // blank lines ahead of it.
            let end = notebook[heading.upperBound...].range(of: "\n## ")?.lowerBound ?? notebook.endIndex
            var at = end
            while at > heading.upperBound, notebook[notebook.index(before: at)] == "\n" { at = notebook.index(before: at) }
            notebook.insert(contentsOf: "\n" + line, at: at)
        } else {
            notebook += "\n\(kind.heading)\n\(line)\n"
        }
        do { try notebook.write(to: url, atomically: true, encoding: .utf8) } catch {
            return ("写不了笔记：\(error.localizedDescription)", true)
        }
        return ("记下了，在「\(kind.heading.dropFirst(3))」：\(url.path)", false)
    }
}
