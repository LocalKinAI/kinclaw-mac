import SwiftUI

/// 「画给我看」 under an answer: the button, then Claude drawing (what it is doing, how long so far),
/// then the drawing itself, live in the conversation — one plays at a time; the others show a still
/// until clicked — with its knobs, a bigger window, and 「改一下」.
struct LiveDrawCard: View {
    let message: ChatMessage
    let question: String
    /// The newest answer gets the button; an older one only keeps the drawing it already has.
    let newest: Bool

    @ObservedObject private var draw = LiveDraw.shared
    @State private var note = ""
    @State private var revising = false

    var body: some View {
        if let id = draw.byMessage[message.id], let job = draw.jobs[id] {
            card(job)
        } else if newest {
            Button { draw.start(question: question, answer: message.content, message: message.id) } label: {
                Label("画给我看", systemImage: "paintbrush.pointed")
            }
            .buttonStyle(.quiet)
            .help("让 Claude 用 huashu 的画法，把这个回答画成一段会动、能拧旋钮去试的讲解（8–15 秒），就在这里实时播。一两分钟到几分钟")
        }
    }

    @ViewBuilder
    private func card(_ job: LiveDraw.Job) -> some View {
        switch job.state {
        case .drawing:
            TimelineView(.periodic(from: job.started, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Claude 在画 · \(Self.elapsed(context.date.timeIntervalSince(job.started))) · \(job.step)")
                        .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("停") { draw.stop(job.id) }.buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.well))
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("没画成：\(job.error ?? "不知道为什么")")
                    .font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(4).textSelection(.enabled)
                Button { draw.retry(job.id) } label: { Label("再画一次", systemImage: "arrow.clockwise") }
                    .buttonStyle(.quiet)
            }
            .frame(maxWidth: 640, alignment: .leading)
        case .ready:
            ready(job)
        }
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
            HStack(spacing: 10) {
                Text(job.title ?? "").font(.kinCaption.weight(.semibold)).lineLimit(1)
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

    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
