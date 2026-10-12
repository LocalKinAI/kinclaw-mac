import AppKit
import WebKit

// MachineCheck against a fixture page, in WebKit, out of sight: events, readout, line check, pictures,
// errors with their message, animation frames off screen. Exit 1 on any failure.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let here = URL(fileURLWithPath: CommandLine.arguments[1])
let skill = URL(fileURLWithPath: CommandLine.arguments[2])
let shots = URL(fileURLWithPath: CommandLine.arguments[3])
let lineEnds = ((try? String(contentsOf: skill.appendingPathComponent("scripts/line-ends.mjs"), encoding: .utf8)) ?? "")
    .components(separatedBy: "\n").filter { !$0.hasPrefix("export const LINE_ENDS") }.joined(separator: "\n")
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print((ok ? "ok   " : "FAIL ") + name + (ok ? "" : "\n     " + detail.suffix(400)))
    if !ok { failures += 1 }
}
Task { @MainActor in
    let check1 = MachineCheck()
    let page = here.appendingPathComponent("fixture.html")
    let steps: [[Any]] = [["wait", 800], ["click", "[data-ctl=press]"], ["click", "[data-ctl=press]"], ["wait", 200],
                          ["eval", "document.querySelector('[data-readout]').textContent"], ["eval", "window.__frames()"],
                          ["lines"], ["shot", "card"]]
    let out = await check1.run(page, steps: steps, shots: shots, lineEnds: lineEnds)
    let text = out.lines.joined(separator: "\n")
    check("clicks reach the page's handler", text.contains("eval: \"按了 2 次\""), text)
    let frames = text.split(separator: "\n").first { $0.hasPrefix("eval: ") && Int($0.dropFirst(6)) != nil }.flatMap { Int($0.dropFirst(6)) } ?? 0
    check("animation frames run off screen (\(frames) in ~1.4 s)", frames > 30, text)
    check("the line check finds the floating line (2 of 4 ends)", text.contains("line ends: 2 of 4 ends on 2 lines float"), text)
    let size = out.pictures.first.flatMap { NSImage(contentsOf: $0) }.flatMap { $0.representations.first }.map { ($0.pixelsWide, $0.pixelsHigh) }
    check("a shot of the card is the card's size (+4 px round)", size.map { $0.0 == 658 && $0.1 == 308 } ?? false, "\(String(describing: size))")
    check("a clean page says so", text.contains("console: clean"), text)
    let bad = await check1.run(here.appendingPathComponent("broken.html"), steps: [["wait", 600]], shots: shots, lineEnds: lineEnds)
    let said = bad.lines.joined(separator: "\n")
    check("an exception comes back with its message", said.contains("TypeError") && said.contains("part.parts"), said)
    print(failures == 0 ? "machine check: all passed" : "machine check: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}
app.run()
