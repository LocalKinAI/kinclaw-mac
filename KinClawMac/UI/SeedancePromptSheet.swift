import AppKit
import SwiftUI

/// awesome-seedance (`SeedanceLibrary`) for the Montage and Film tabs: a template to fill in or a
/// case to start from, read, changed and handed to the tab's agent — with a note that it is to be
/// filmed on the box with H3 and LTX, not by Seedance.
struct SeedancePromptSheet: View {
    @ObservedObject var agent: StudioAgent
    /// Film's agent works with the Film tools; Montage's in OpenMontage.
    let film: Bool
    @ObservedObject private var library = SeedanceLibrary.shared
    @Environment(\.dismiss) private var dismiss

    private enum Shelf: String, CaseIterable { case templates = "模板", cases = "案例" }
    private enum Filter: String, CaseIterable { case all = "全部", h3 = "H3 拍得出", v25 = "Seedance 2.5", v20 = "Seedance 2.0" }

    @State private var shelf: Shelf = .templates
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var template: SeedanceLibrary.Template?
    @State private var item: SeedanceLibrary.Case?
    @State private var text = ""
    @State private var copied = false

    private var shownCases: [SeedanceLibrary.Case] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return library.cases.filter { c in
            let kept: Bool
            switch filter {
            case .all: kept = true
            case .h3: kept = c.onH3 == .reproduced
            case .v25: kept = c.model.contains("2.5")
            case .v20: kept = c.model.contains("2.0")
            }
            return kept && (q.isEmpty || c.title.lowercased().contains(q) || c.prompt.lowercased().contains(q)
                            || c.summary.lowercased().contains(q) || c.creator.lowercased().contains(q))
        }
    }

    private var categories: [String] {
        library.templates.reduce(into: [String]()) { if !$0.contains($1.category) { $0.append($1.category) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Seedance 提示词").font(.system(size: 14, weight: .semibold))
                Link("awesome-seedance", destination: SeedanceLibrary.home).font(.system(size: 10))
                Text("CC BY 4.0 · goodcase.ai · \(library.templates.count) 个模板 · \(library.cases.count) 个案例")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                if library.loading { ProgressView().controlSize(.small) }
                Button { Task { await library.load(fresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(library.loading)
                    .help("去 GitHub 看有没有更新（只拿改过的文件）")
                Button("关") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Picker("", selection: $shelf) {
                        ForEach(Shelf.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if shelf == .templates { templateList } else { caseList }
                }
                .frame(width: 320)
                .padding(8)
                Divider()
                detail.padding(10)
            }
        }
        .frame(minWidth: 960, minHeight: 660)
        .task { await library.load() }
    }

    // MARK: Lists

    private var templateList: some View {
        List(selection: Binding(get: { template?.id }, set: { id in pick(library.templates.first { $0.id == id }) })) {
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    ForEach(library.templates.filter { $0.category == category }) { t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.system(size: 11.5))
                            Text(t.summary).font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(2)
                        }
                        .tag(t.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var caseList: some View {
        VStack(spacing: 6) {
            TextField("搜：咖啡、vlog、产品、作者…", text: $search).textFieldStyle(.roundedBorder)
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .help("H3 拍得出：awesome-seedance 拿 MiniMax H3（盒子上拍片的就是它）重测过、照样拍出来的")
            List(shownCases, selection: Binding(get: { item?.id }, set: { id in pick(library.cases.first { $0.id == id }) })) { c in
                HStack(spacing: 6) {
                    AsyncImage(url: c.poster) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                        .frame(width: 56, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.system(size: 11)).lineLimit(2)
                        Text([c.model, "热度 \(c.heat)", c.onH3?.title].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 9)).foregroundColor(c.onH3 == .reproduced ? .green : .secondary)
                    }
                }
                .tag(c.id)
            }
            .listStyle(.plain)
        }
    }

    private func pick(_ t: SeedanceLibrary.Template?) {
        template = t
        item = nil
        text = t?.copy ?? ""
        copied = false
    }

    private func pick(_ c: SeedanceLibrary.Case?) {
        item = c
        template = nil
        text = c?.prompt ?? ""
        copied = false
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let t = template, shelf == .templates {
            VStack(alignment: .leading, spacing: 8) {
                Text(t.title).font(.system(size: 13, weight: .semibold))
                Text("\(t.category) · 已归类 \(t.caseCount) 个案例").font(.system(size: 10)).foregroundColor(.secondary)
                Text(t.summary).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Text("把【】换成你要拍的，交给 agent：它照这个写法出一个在盒子上用 H3 / LTX 拍的方案")
                    .font(.system(size: 10)).foregroundColor(.orange)
                editor(original: t.copy) { library.handover(t, text: text, film: film) }
            }
        } else if let c = item, shelf == .cases {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: c.poster) { $0.resizable().scaledToFit() } placeholder: { Color.primary.opacity(0.06) }
                        .frame(width: 240, height: 135).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.title).font(.system(size: 13, weight: .semibold))
                        Text(c.summary).font(.system(size: 10.5)).foregroundColor(.secondary)
                            .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text("\(c.model) · 热度 \(c.heat)").font(.system(size: 10)).foregroundColor(.secondary)
                            if let source = c.source { Link(c.creator.isEmpty ? "原帖" : c.creator, destination: source).font(.system(size: 10)) }
                            if let video = c.video { Link("看成片", destination: video).font(.system(size: 10)) }
                        }
                        if let verdict = c.onH3 {
                            Text(verdict.title + (verdict == .reproduced ? "：盒子上照着拍有把握" : "：要改了再拍"))
                                .font(.system(size: 10)).foregroundColor(verdict == .reproduced ? .green : .orange)
                        } else {
                            Text("还没在 H3 上重测过").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                editor(original: c.prompt) { library.handover(c, prompt: text, film: film) }
            }
        } else {
            VStack {
                Spacer()
                Text(library.trouble ?? (library.templates.isEmpty && library.loading
                                         ? "第一次要从 GitHub 拿模板和七百多个案例，十几秒…" : "左边挑一个"))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func editor(original: String, handover: @escaping () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text).font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden).padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
            HStack {
                Button(copied ? "已复制" : "复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                if text != original { Button("还原") { text = original } }
                Spacer()
                Button(agent.running ? "说给正在跑的 agent" : "交给 agent") {
                    agent.say(handover())
                    dismiss()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("交给\(film ? " Film" : " Montage ")的 agent（\(agent.brainTitle)），附一句：Seedance 不在盒子上，改成 H3 / LTX 能拍的方案，先给你看再拍")
            }
        }
    }
}
