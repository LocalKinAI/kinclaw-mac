import Foundation

/// Curated list of common (provider, model) combos kincode can run
/// against. Surfaced as a dropdown in two places:
///
///   1. **Code tab → repoBar** — live switch via POST /api/brain.
///      Affects the *running* kincode subprocess only; the next turn
///      uses the new brain. Doesn't persist to UserDefaults.
///   2. **Settings → Backend → Kincode** — picks the *default* brain
///      that KinCodeSupervisor passes via -provider / -model when
///      it spawns kincode at app launch. Persisted to UserDefaults
///      under `kinclaw.kincode.brain.provider` / `.brain.model`.
///
/// The two are independent on purpose: the Code-tab dropdown lets
/// you experiment ("does Claude do this better than Kimi?") without
/// changing the default. Settings is for "I always want Claude" —
/// reflects across relaunches.
///
/// Adding a new preset: append to `presets` below. The list is
/// hardcoded — power users with custom Ollama models can edit
/// UserDefaults directly or extend this list, but the curated set
/// keeps the dropdown short.
struct BrainPreset: Identifiable, Hashable {
    /// Stable identifier — `<provider>/<model>`.
    var id: String { "\(provider)/\(model)" }

    /// Provider name as kincode expects: "ollama", "anthropic", "openai".
    let provider: String

    /// Model identifier as the provider expects (e.g. "kimi-k2.6:cloud",
    /// "claude-sonnet-4-6", "gpt-4o").
    let model: String

    /// Human-readable label for the dropdown row.
    let label: String

    /// Env var the user needs set for this preset to work — nil for
    /// local Ollama. UI can add a ⚠ marker when the var is missing.
    let needsEnv: String?

    /// Short tag shown alongside the label (e.g. "free", "needs key").
    var tag: String? {
        if needsEnv != nil { return "needs key" }
        if model.hasSuffix(":cloud") { return "ollama cloud" }
        return "local"
    }

    static let presets: [BrainPreset] = [
        // Ollama Cloud — the default. Free if user has Ollama Cloud.
        BrainPreset(provider: "ollama", model: "kimi-k2.6:cloud",
                    label: "Kimi K2.6", needsEnv: nil),
        BrainPreset(provider: "ollama", model: "kimi-k2.5:cloud",
                    label: "Kimi K2.5", needsEnv: nil),
        BrainPreset(provider: "ollama", model: "deepseek-v4-pro:cloud",
                    label: "DeepSeek V4 Pro", needsEnv: nil),
        BrainPreset(provider: "ollama", model: "minimax-m2.7:cloud",
                    label: "Minimax M2.7", needsEnv: nil),

        // Local Ollama — works fully offline.
        BrainPreset(provider: "ollama", model: "qwen3:8b",
                    label: "Qwen3 8B (local)", needsEnv: nil),
        BrainPreset(provider: "ollama", model: "llama3.3:8b",
                    label: "Llama 3.3 8B (local)", needsEnv: nil),

        // Anthropic — needs ANTHROPIC_API_KEY or kincode -login.
        BrainPreset(provider: "anthropic", model: "claude-sonnet-4-6",
                    label: "Claude Sonnet 4.6", needsEnv: "ANTHROPIC_API_KEY"),
        BrainPreset(provider: "anthropic", model: "claude-haiku-4-5-20251001",
                    label: "Claude Haiku 4.5", needsEnv: "ANTHROPIC_API_KEY"),

        // OpenAI.
        BrainPreset(provider: "openai", model: "gpt-4o",
                    label: "GPT-4o", needsEnv: "OPENAI_API_KEY"),
        BrainPreset(provider: "openai", model: "gpt-4-turbo",
                    label: "GPT-4 Turbo", needsEnv: "OPENAI_API_KEY"),
    ]

    /// Find the preset matching a (provider, model) combo, if any.
    /// Returns nil for unknown combos so callers can fall back to
    /// "Custom — <model>" in the UI rather than misrepresenting.
    static func find(provider: String, model: String) -> BrainPreset? {
        presets.first { $0.provider == provider && $0.model == model }
    }
}
