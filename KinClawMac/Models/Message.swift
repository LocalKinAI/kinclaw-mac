import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    /// Tool invocations attached to this message — populated by the
    /// local kinclaw transport from `tool_call` / `tool_result`
    /// SSE events. Cloud agents don't emit these; the array stays
    /// empty for cloud bubbles. Renderered as collapsible sections
    /// below the assistant text.
    var toolCalls: [ToolCall] = []
    /// File attachments — image / video / generic file paths.
    /// User bubbles get them from drag-and-drop into the input bar;
    /// assistant bubbles get them from kinclaw `screen_frame` /
    /// `tool_result` events that carry `images` / `urls` / `path`
    /// fields. Rendered as inline previews (image / video / file
    /// icon) below the message content.
    var attachments: [Attachment] = []

    enum Role: String {
        case user
        case assistant
        case system
    }

    var isUser: Bool { role == .user }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, timestamp: Date())
    }

    static func assistant(_ text: String = "") -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, timestamp: Date())
    }
}

/// One tool invocation emitted by a local kinclaw turn. Stored on
/// the assistant `ChatMessage` it belongs to, displayed inline as
/// an expandable widget.
struct ToolCall: Identifiable, Equatable {
    let id: String   // server-issued tool_call id; falls back to UUID
    let name: String
    let params: [String: String]
    /// Output filled in once the matching tool_result event arrives.
    /// Stays nil until then — UI renders as "running…" while nil.
    var output: String?
}

/// A file or media reference attached to a `ChatMessage`. Could be a
/// local file path the user drag-dropped, a screenshot the agent
/// produced, or a remote `/file/...` URL served by kinclaw.
struct Attachment: Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: Kind
    /// File URL on disk (local path) — preferred when present.
    let localURL: URL?
    /// Remote URL — used for kinclaw `/file/...` paths or cloud assets.
    let remoteURL: URL?
    /// Display name fallback when we don't have a file path.
    let displayName: String

    enum Kind: String, Hashable {
        case image    // png / jpg / heic / gif / webp
        case video    // mp4 / mov
        case file     // anything else
    }

    init(localURL: URL) {
        self.id = UUID()
        self.localURL = localURL
        self.remoteURL = nil
        self.displayName = localURL.lastPathComponent
        self.kind = Self.kindFor(extension: localURL.pathExtension)
    }

    init(remoteURL: URL, displayName: String? = nil) {
        self.id = UUID()
        self.localURL = nil
        self.remoteURL = remoteURL
        self.displayName = displayName
            ?? remoteURL.lastPathComponent
        self.kind = Self.kindFor(extension: remoteURL.pathExtension)
    }

    /// Map a file extension → kind so the renderer picks the right
    /// view (Image / VideoPlayer / icon-card).
    private static func kindFor(extension ext: String) -> Kind {
        let e = ext.lowercased()
        let images: Set<String> = ["png", "jpg", "jpeg", "heic", "heif",
                                    "gif", "webp", "bmp", "tiff"]
        let videos: Set<String> = ["mp4", "mov", "m4v", "webm"]
        if images.contains(e) { return .image }
        if videos.contains(e) { return .video }
        return .file
    }

    /// Best URL for fetch / display — prefer local, fall back to remote.
    var bestURL: URL? { localURL ?? remoteURL }
}

// MARK: - API Request / Response

struct ChatRequest: Codable {
    let messages: [APIMessage]
    let stream: Bool
    let noHistory: Bool?

    enum CodingKeys: String, CodingKey {
        case messages, stream
        case noHistory = "no_history"
    }
}

struct APIMessage: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Codable {
    let id: String?
    let choices: [Choice]?

    struct Choice: Codable {
        let index: Int?
        let message: ResponseMessage?
        let delta: ResponseDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message, delta
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String?
        let content: String?
    }

    struct ResponseDelta: Codable {
        let role: String?
        let content: String?
    }
}
