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
