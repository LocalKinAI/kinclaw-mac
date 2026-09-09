import SwiftUI

/// The gate, as one thing you can point at and change.
///
/// The kernel has two switches — the approval gate (`ask` / `auto`) and
/// plan mode (read-only) — and until now the first was only settable in
/// the soul file and the second was an icon nobody could name. Claude
/// Code puts the same idea in the corner of the composer: one label
/// that says what the agent is allowed to do right now, and a click to
/// change it.
enum GateMode: String, CaseIterable, Identifiable {
    /// Read-only. It investigates and proposes; nothing is touched.
    case plan
    /// The soul's ask rules apply — risky calls stop for approval.
    case ask
    /// Everything the soul exposes runs without stopping.
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plan: return "只看不动"
        case .ask:  return "先问我"
        case .auto: return "放手干"
        }
    }

    var icon: String {
        switch self {
        case .plan: return "list.clipboard"
        case .ask:  return "hand.raised"
        case .auto: return "bolt"
        }
    }

    var tint: Color {
        switch self {
        case .plan: return .orange
        case .ask:  return .secondary
        case .auto: return .yellow
        }
    }

    var help: String {
        switch self {
        case .plan: return "只看不动 —— 它能读、能查，但点击、输入、跑命令、写文件全部拒绝，先给你一个方案"
        case .ask:  return "先问我 —— 魂里列为危险的调用会停下来等你点头（这是默认）"
        case .auto: return "放手干 —— 不再拦截。只在你盯着屏幕、且知道它要做什么时用"
        }
    }

    /// Derive the label from the two kernel switches.
    static func from(permissionMode: String, planMode: Bool) -> GateMode {
        if planMode { return .plan }
        return permissionMode == "auto" ? .auto : .ask
    }
}

/// The composer-footer control: current mode as a small label, click to
/// pick another.
struct PermissionModePicker: View {
    let mode: GateMode
    let onPick: (GateMode) -> Void

    var body: some View {
        Menu {
            ForEach(GateMode.allCases) { m in
                Button {
                    onPick(m)
                } label: {
                    if m == mode {
                        Label(m.label, systemImage: "checkmark")
                    } else {
                        Label(m.label, systemImage: m.icon)
                    }
                }
                .help(m.help)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                Text(mode.label)
                    .font(.system(size: 11))
            }
            .foregroundColor(mode == .ask ? .secondary : mode.tint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(mode.help)
    }
}
