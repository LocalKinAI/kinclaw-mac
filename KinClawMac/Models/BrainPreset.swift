import Foundation

/// One (provider, model) a brain menu can offer: Cowork's brain, the
/// terminal agents' model, the Studio agents' seats. Most rows come from
/// whatever the configured Ollama has pulled (`OllamaCatalog.loadPresets`);
/// `fallbackPresets` is what a menu shows before that answers.
///
/// (It began as the brain menu of kincode, the old Code mode's kernel,
/// retired 2026-10-10.)
struct BrainPreset: Identifiable, Hashable {
    /// Stable identifier — `<provider>/<model>`.
    var id: String { "\(provider)/\(model)" }

    /// Provider name as the kernels expect: "ollama", "anthropic", "openai".
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

    /// Minimal fallback used only when Ollama is unreachable on app
    /// launch (rare — the supervisor + the existing kinclaw kernel
    /// both depend on Ollama, so a working setup will always have it).
    /// The dynamic catalog (`OllamaCatalog.loadPresets`) replaces this
    /// list with the user's actual installed models.
    static let fallbackPresets: [BrainPreset] = [
        BrainPreset(provider: "ollama", model: "kimi-k2.6:cloud",
                    label: "kimi-k2.6 (cloud)", needsEnv: nil),
    ]

    /// Find the preset matching a (provider, model) combo within a
    /// candidate list. Returns nil for unknown combos so callers can
    /// fall back to displaying the raw model string.
    static func find(provider: String, model: String,
                     in presets: [BrainPreset]) -> BrainPreset? {
        presets.first { $0.provider == provider && $0.model == model }
    }
}
