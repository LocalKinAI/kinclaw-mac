import SwiftUI

/// Which coding agent: Claude Code or Codex, the ones not installed greyed.
struct HarnessMenu: View {
    let harness: AgentHarness
    var help = "用哪个 agent：Claude Code 或 Codex"
    let pick: (AgentHarness) -> Void

    var body: some View {
        Menu {
            ForEach(AgentHarness.allCases, id: \.self) { choice in
                Button { pick(choice) } label: {
                    Label(choice.title + (choice.binary == nil ? "（这台 Mac 没装）" : ""),
                          systemImage: choice == harness ? "checkmark" : "")
                }
                .disabled(choice.binary == nil)
            }
        } label: {
            ChipLabel(title: harness.title, symbol: "terminal", menu: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(help)
    }
}

/// What an agent thinks with, every place a brain can come from grouped:
/// the harness's own sign-in, this Mac's Ollama, the box's Ollama and kinfer.
struct BrainMenu: View {
    @ObservedObject private var catalog = BrainCatalog.shared
    let harness: AgentHarness
    let brain: AgentBrain
    var help = "agent 用哪个模型想事情：它自己登录的账号（Claude 订阅 / ChatGPT）、这台 Mac 的 Ollama、盒子上的 Ollama 或 kinfer"
    let pick: (AgentBrain) -> Void

    var body: some View {
        Menu {
            ForEach(AgentBrain.Source.allCases, id: \.self) { source in
                Section(AgentBrain.section(source, for: harness)) {
                    if source == .account {
                        choice(.account)
                    } else if let models = catalog.models[source], !models.isEmpty {
                        ForEach(models, id: \.self) { model in choice(AgentBrain(source: source, model: model)) }
                    } else {
                        Text(catalog.models[source] == nil ? "在问…" : "没连上，或者没有模型")
                    }
                }
            }
        } label: {
            ChipLabel(title: brain.title(for: harness), symbol: "brain", menu: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(help)
        .task { await catalog.refresh() }
    }

    private func choice(_ candidate: AgentBrain) -> some View {
        Button { pick(candidate) } label: {
            Label(candidate.title(for: harness), systemImage: candidate == brain ? "checkmark" : "")
        }
    }
}
