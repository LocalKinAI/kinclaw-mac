import SwiftUI

/// 「画给我看」 under an answer: the button, then Claude drawing (what it is doing, how long so far),
/// then the drawing itself, live in the conversation — one plays at a time; the others show a still
/// until clicked — with its knobs, a bigger window, and 「改一下」. Beside it 「做成一台机器」, the second
/// way (LiveMachine): made in the background, then touched right here.
struct LiveDrawCard: View {
    let message: ChatMessage
    let question: String
    /// The newest answer gets the button; an older one only keeps the drawing it already has.
    let newest: Bool

    @ObservedObject private var draw = LiveDraw.shared
    @ObservedObject private var machines = LiveMachine.shared
    @ObservedObject private var touched = LiveMachine.shared.inline
    @State private var note = ""
    @State private var revising = false

    var body: some View {
        if let id = draw.byMessage[message.id], let job = draw.jobs[id] {
            card(job)
        } else if newest {
            HStack(spacing: 14) {
                Button { draw.start(question: question, answer: message.content, message: message.id) } label: {
                    Label("画给我看", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.quiet)
                .help("让 Claude 用 huashu 的画法，把这个回答画成一段会动、能拧旋钮去试的讲解（8–15 秒），就在这里实时播。一两分钟到几分钟")
                // A machine is half an hour and a dollar or two of Claude: for an answer that explains
                // something, not a greeting (two were made for 「你好」, 2026-10-10).
                if Self.explains(message.content) {
                    Button { draw.start(question: question, answer: message.content, message: message.id, style: .machine) } label: {
                        Label("做成一台机器", systemImage: "gearshape.2")
                    }
                    .buttonStyle(.quiet)
                    .help("让 Claude 用 anatomy 的做法，把这个道理做成一台能摸的小机器：等轴测、几十个精细的零件、读数是真的，能按、能拧、能拖。"
                          + "在后台做，几分钟到半小时，做好了通知你，就在这里摸。一台约 $1–2.5 的 Claude 用量（按 API 价折算）")
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ job: LiveDraw.Job) -> some View {
        let machine = job.style == .machine
        switch job.state {
        case .drawing:
            TimelineView(.periodic(from: job.started, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Claude \(machine ? "在做机器" : "在画") · \(Self.elapsed(context.date.timeIntervalSince(job.started))) · \(job.step)")
                        .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("停") { draw.stop(job.id) }.buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.well))
            .help(machine ? "在后台做，一刻钟到半小时；做好了会通知你，就在这里摸" : "")
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("没\(machine ? "做" : "画")成：\(job.error ?? "不知道为什么")")
                    .font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(4).textSelection(.enabled)
                HStack(spacing: 14) {
                    // Cut off by a relaunch: on from where it was, in the same Claude conversation.
                    if job.cut, job.session != nil {
                        Button { draw.resume(job.id) } label: { Label("接着做", systemImage: "play.fill") }
                            .buttonStyle(.quiet)
                            .help("接着刚才那段 Claude 对话，从文件夹里已经做好的部分往下做，不从头再来")
                    }
                    Button { draw.retry(job.id) } label: { Label(machine ? "再做一次" : "再画一次", systemImage: "arrow.clockwise") }
                        .buttonStyle(.quiet)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        case .ready:
            if machine { touchable(job) } else { ready(job) }
        }
    }

    /// A machine made: its still until clicked, then the page itself, to press, turn and drag.
    private func touchable(_ job: LiveDraw.Job) -> some View {
        let live = machines.active == job.id
        let kept = machines.machines.first { $0.id == job.id }
        return VStack(alignment: .leading, spacing: 7) {
            Group {
                if live {
                    MachinePageView(page: machines.inline)
                        .frame(height: max(160, touched.height > 0 ? touched.height : (kept?.height ?? 600)))
                } else {
                    ZStack {
                        Color(nsColor: NSColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xef / 255, alpha: 1))
                        if let poster = job.poster, let image = NSImage(contentsOf: poster) {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        }
                        Label("摸一摸", systemImage: "hand.point.up.left.fill")
                            .font(.kinLabel.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.62)))
                            .shadow(radius: 4)
                    }
                    .frame(minHeight: 160)
                    .contentShape(Rectangle())
                    .onTapGesture { machines.activate(job.id) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Text(job.title ?? "").font(.kinCaption.weight(.semibold)).lineLimit(1)
                Self.spent(job)
                Spacer(minLength: 8)
                Button { revising.toggle() } label: { Label("改一下", systemImage: "pencil") }
                    .buttonStyle(.quiet)
                Button { machines.show(job.id) } label: {
                    Label("大窗口", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.quiet)
                Button { machines.openInBrowser(job.id) } label: { Label("浏览器", systemImage: "safari") }
                    .buttonStyle(.quiet)
                    .help("这一页不靠别的文件：可以存下来、发给别人")
            }
            if revising {
                HStack(spacing: 8) {
                    TextField("怎么改：零件再多一些、读数换成百分比、加一个旋钮……", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button("改", action: submit)
                        .buttonStyle(.quietFilled)
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func ready(_ job: LiveDraw.Job) -> some View {
        let live = draw.playing == job.id
        return VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Color.black
                if live {
                    LivePlayerView(player: draw.inline)
                } else {
                    if let poster = job.poster, let image = NSImage(contentsOf: poster) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 6)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { if !live { draw.activate(job.id) } }
            if live {
                LiveControls(player: draw.inline, spaceBar: false)
                LiveOptions(player: draw.inline, full: false)
            }
            if let scoring = job.scoring {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(scoring).font(.kinCaption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Text(job.title ?? "").font(.kinCaption.weight(.semibold)).lineLimit(1)
                Self.spent(job)
                Spacer(minLength: 8)
                LiveOutButtons(id: job.id, player: draw.inline)
                Button { revising.toggle() } label: { Label("改一下", systemImage: "pencil") }
                    .buttonStyle(.quiet)
                Button { draw.inline.pause(); Task { await LiveFilm.shared.show(job.id) } } label: {
                    Label("大窗口", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.quiet)
                .help("在活画的窗口里放：能全屏、能慢放")
            }
            if revising {
                HStack(spacing: 8) {
                    TextField("怎么改：字大一点、换成水墨、多画一颗行星……", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button("改", action: submit)
                        .buttonStyle(.quietFilled)
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func submit() {
        guard let id = draw.byMessage[message.id] else { return }
        draw.revise(id, note: note)
        note = ""
        revising = false
    }

    /// An answer that explains something — long enough to have an idea in it — rather than a greeting
    /// or a one-line reply.
    static func explains(_ answer: String) -> Bool {
        answer.filter { !$0.isWhitespace }.count >= 200
    }

    /// What it cost and how long it took, quietly beside its title.
    @ViewBuilder
    static func spent(_ job: LiveDraw.Job) -> some View {
        if let spent = job.spent {
            Text(spent)
                .font(.kinCaption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Claude Code 报的花费（按 API 价折算；用订阅时算在订阅的用量里），和最后一次画用了多久")
        }
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
