import SwiftUI

/// The box's ComfyUI at a glance, in the titlebar while the Studio is open — 「你在 kinclaw-mac
/// 加个 status 可以看见啊」(2026-09-30). One line: idle, or whose job runs at which step and for
/// how long, and how many wait; a click opens the whole desk (`BoxDeskView`). Read from the
/// progress desk on the box through `ComfyWatch`, which polls only while this is on screen.
struct BoxStatusChip: View {
    @ObservedObject private var watch = ComfyWatch.shared
    @ObservedObject private var services = BoxServices.shared
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(line).font(.system(size: 11.5)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(hovering || open ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(hovering || open ? Theme.hover : Theme.well))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
        .help("盒子的 ComfyUI：在跑什么、第几步、排队几个、最近谁打断过（点开看全部）")
        .popover(isPresented: $open, arrowEdge: .bottom) { BoxDeskView() }
        .onAppear { watch.watchBox() }
        .onDisappear { watch.unwatchBox() }
    }

    private var dot: Color {
        guard watch.boxAt != nil, let box = watch.box else { return Theme.notice }
        return box.running.isEmpty ? Color.secondary.opacity(0.5) : Theme.good
    }

    private var line: String {
        guard watch.boxAt != nil, let box = watch.box else {
            return services.blocked ? "盒子：本地网络被挡" : "盒子：连不上"
        }
        guard let job = box.running.first else {
            return box.pending.isEmpty ? "盒子空着" : "盒子：排队 \(box.pending.count) 个"
        }
        // Short, it lives in the titlebar: "Film H3 镜头 2/4 · 7:40 +1".
        var out = "\(job.tab ?? "盒子") \(job.what ?? "工作流")"
        if let value = job.value, let max = job.max, max > 1 { out += " \(Int(value))/\(Int(max))" }
        if let seconds = job.for_s { out += " · \(ComfyWatch.clock(seconds))" }
        if !box.pending.isEmpty { out += " +\(box.pending.count)" }
        return out
    }
}

/// The whole desk: what runs (whose, which node and step, for how long, sent from where),
/// what waits and for how long, and how the last jobs ended — an interruption with who and why.
struct BoxDeskView: View {
    @ObservedObject private var watch = ComfyWatch.shared
    @ObservedObject private var services = BoxServices.shared
    @ObservedObject private var turnTaker = TurnTaker.shared
    @ObservedObject private var omni = OmniCall.shared
    @ObservedObject private var liveFace = LiveFace.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("盒子的 ComfyUI").font(.system(size: 14, weight: .semibold))
                Text("Film、Motion、Comfy、Pixelle、Montage 共用").font(.kinCaption).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                if let at = watch.boxAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, Int(context.date.timeIntervalSince(at)))) 秒前").font(.kinCaption).foregroundStyle(.tertiary)
                    }
                }
            }
            if watch.boxAt == nil || watch.box == nil {
                Text(services.blocked ? BoxServices.blockedAdvice
                     : "连不上盒子的 ComfyUI：盒子关着，或 ComfyUI 没起来（Settings → Backend → 盒子上的服务）")
                    .font(.kinLabel).foregroundStyle(Theme.notice).fixedSize(horizontal: false, vertical: true)
            }
            if let box = watch.box {
                section("在跑") {
                    if box.running.isEmpty {
                        Text("没有").font(.kinLabel).foregroundStyle(.secondary)
                    }
                    ForEach(box.running, id: \.prompt_id) { job in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle().fill(Theme.good).frame(width: 7, height: 7)
                                Text(job.title).font(.system(size: 12.5, weight: .medium))
                                Spacer(minLength: 8)
                                if let seconds = job.for_s { Text("已 \(ComfyWatch.clock(seconds))").font(.kinLabel).monospacedDigit() }
                            }
                            Text(stepLine(job)).font(.kinCaption).foregroundStyle(.secondary).padding(.leading, 13)
                            if let origin = origin(job.program, job.from) {
                                Text(origin).font(.kinCaption).foregroundStyle(.tertiary).padding(.leading, 13)
                            }
                        }
                    }
                }
                section(box.pending.isEmpty ? "排队" : "排队 \(box.pending.count)") {
                    if box.pending.isEmpty {
                        Text("没有").font(.kinLabel).foregroundStyle(.secondary)
                    }
                    ForEach(Array(box.pending.enumerated()), id: \.element.prompt_id) { index, job in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)").font(.kinCaption).foregroundStyle(.tertiary).frame(width: 14, alignment: .trailing)
                            Text(job.title).font(.kinLabel)
                            Spacer(minLength: 8)
                            if let waited = job.waiting_s { Text("等了 \(ComfyWatch.clock(waited))").font(.kinCaption).foregroundStyle(.secondary) }
                            if let origin = origin(job.program, job.from) { Text(origin).font(.kinCaption).foregroundStyle(.tertiary) }
                        }
                    }
                }
                // The companion's two services on the box — 「kinclaw-mac 盒子状态可以看看」.
                section("陪伴") {
                    companionRow("小回合（Smart Turn + MaAI）", services.states[.turn],
                                 detail: turnTaker.connected ? "正在听你说话" : nil)
                    companionRow("MiniCPM-o 全双工", services.states[.omni],
                                 detail: omni.state == .live ? (omni.seeing ? "通话中 · 看着你" : "通话中") : nil)
                    companionRow("实时口型（Ditto + QuickTalk）", services.states[.face],
                                 detail: liveFace.connected ? (liveFace.talking ? "她在说话" : "在线，待机中") : nil)
                }
                section("最近结束") {
                    let ended = Array(box.ended.suffix(6).reversed())
                    if ended.isEmpty {
                        Text("还没有").font(.kinLabel).foregroundStyle(.secondary)
                    }
                    ForEach(ended, id: \.prompt_id) { job in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(job.at.map { Self.time.string(from: Date(timeIntervalSince1970: $0)) } ?? "")
                                    .font(.kinCaption).foregroundStyle(.tertiary).monospacedDigit()
                                Text(job.title).font(.kinLabel)
                                Spacer(minLength: 8)
                                Text(endWord(job)).font(.kinCaption).foregroundStyle(endColor(job))
                            }
                            if job.end == "interrupted" {
                                Text(stopper(job)).font(.kinCaption).foregroundStyle(Theme.notice).padding(.leading, 44)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if job.end == "error", let error = job.error, !error.isEmpty {
                                Text(error).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 44)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            watch.watchBox()
            Task { await services.refresh() }
        }
        .onDisappear { watch.unwatchBox() }
    }

    private func companionRow(_ title: String, _ state: BoxServices.State?, detail: String?) -> some View {
        HStack(spacing: 8) {
            Circle().fill(state == .up ? Theme.good : state == .down ? Color.secondary.opacity(0.5) : Theme.notice)
                .frame(width: 7, height: 7)
            Text(title).font(.kinLabel)
            Spacer(minLength: 8)
            Text(detail ?? {
                switch state {
                case .up: return "在跑"
                case .down: return "没开（设置 → Backend → 盒子上的服务）"
                case .starting: return "在起"
                case .stopping: return "在停"
                default: return "…"
                }
            }())
            .font(.kinCaption).foregroundStyle(.secondary)
        }
    }

    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func stepLine(_ job: ComfyWatch.Job) -> String {
        var out = job.node_class ?? "准备中"
        if let value = job.value, let max = job.max, max > 1 {
            out += " 第 \(Int(value))/\(Int(max)) 步" + (job.step_s.map { "，这一步 \(ComfyWatch.clock($0))" } ?? "")
        } else if let seconds = job.node_s {
            out += "，这个节点 \(ComfyWatch.clock(seconds))"
        }
        return out
    }

    private func origin(_ program: String?, _ from: String?) -> String? {
        let parts = [program, from].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func endWord(_ job: ComfyWatch.Ended) -> String {
        let took = job.took_s.map { " · \(ComfyWatch.clock($0))" } ?? ""
        switch job.end {
        case "done": return "完成" + took
        case "error": return "出错" + took
        case "interrupted": return "被打断" + took
        default: return job.end ?? ""
        }
    }

    private func endColor(_ job: ComfyWatch.Ended) -> Color {
        switch job.end {
        case "error": return Theme.bad
        case "interrupted": return Theme.notice
        default: return .secondary
        }
    }

    private func stopper(_ job: ComfyWatch.Ended) -> String {
        if let by = job.by { return "\(by)" + (job.why.map { "：\($0)" } ?? "") }
        let source = [job.stop_program, job.stop_from].compactMap { $0 }.joined(separator: " · ")
        return source.isEmpty ? "没人留话（可能是 ComfyUI 页面上点的停）" : "\(source)，没留原因"
    }
}
