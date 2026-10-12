import Foundation

/// When the cloud brain's quota runs out (Ollama Cloud: "you have reached your weekly usage limit"),
/// the conversation goes on with a model on the box instead of dying until somebody notices. On
/// 2026-10-10 Chat and Talk were dead from 20:18 to 21:28: a relaunch had put the kernel back on its
/// soul's kimi-k2.6:cloud, out of quota for the week. A runtime switch, the same the model menu makes —
/// souls, settings and the box's models untouched (「都做吧」, 2026-10-11).
@MainActor
enum BrainFallback {
    /// The box model it goes to: ornith, unless Settings say another.
    static let modelKey = "kinclaw.brain.fallback.model"
    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? "ornith-1.5:35b" }

    /// A cloud provider saying its quota is spent — not a broken turn.
    static func isQuota(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("usage limit") || text.contains("upgrade for higher limits")
            || (text.contains("429") && text.contains("limit"))
    }

    /// The kernel switched to the box's model: what to tell the person; nil when there is no box, the
    /// box's Ollama does not have the model, or the kernel would not switch.
    static func switchFromCloud(current: String) async -> String? {
        guard let host = BrainCatalog.boxHost else { return nil }
        let endpoint = "http://\(host):11434"
        let fallback = model
        guard fallback != current,
              await OllamaCatalog.loadPresets(baseURL: endpoint).contains(where: { $0.model == fallback }) else { return nil }
        do {
            try await KinClawAPIClient.default.switchBrain(provider: "ollama", model: fallback, endpoint: endpoint)
        } catch {
            return nil
        }
        return "云端模型\(current.isEmpty ? "" : "（\(current)）")这周的额度用完了：这段对话改用盒子上的 \(fallback) 接着说。"
            + "额度恢复后，在模型菜单里切回来就行。"
    }
}
