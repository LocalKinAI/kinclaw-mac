import Foundation
import SwiftUI

// MARK: - KinBook Post

struct Post: Codable, Identifiable {
    let id: String
    let board: String?
    let topic: String?
    let type: String?          // debate, briefing, article
    let verdict: String?
    let winner: String?
    let consensusRatio: Double?
    let participants: Int?
    let roundsCompleted: Int?
    let positionChanges: Int?
    let conductor: String?
    let verdictDetail: String?
    let severityCritical: Int?
    let severityWarning: Int?
    let severityInfo: Int?
    let createdAt: String?
    let pinned: Bool?
    let status: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id, board, topic, type, verdict, winner, participants, conductor, pinned, status, summary
        case consensusRatio = "consensus_ratio"
        case roundsCompleted = "rounds_completed"
        case positionChanges = "position_changes"
        case verdictDetail = "verdict_detail"
        case severityCritical = "severity_critical"
        case severityWarning = "severity_warning"
        case severityInfo = "severity_info"
        case createdAt = "created_at"
    }

    var displayType: String {
        switch type {
        case "debate": return "DEBATE"
        case "briefing": return "BRIEFING"
        case "article": return "ARTICLE"
        default: return "POST"
        }
    }

    var typeColor: String {
        switch type {
        case "debate": return "purple"
        case "briefing": return "orange"
        case "article": return "blue"
        default: return "gray"
        }
    }

    // SF Symbol name for verdict
    var verdictIcon: String {
        let v = verdict?.lowercased() ?? ""
        if v.contains("consensus") { return "checkmark.circle.fill" }
        if v.contains("split") || v.contains("lean") { return "scale.3d" }
        if v.contains("deadlock") { return "lock.fill" }
        return "doc.text.fill"
    }

    var verdictColor: Color {
        let v = verdict?.lowercased() ?? ""
        if v.contains("consensus") { return .green }
        if v.contains("split") || v.contains("lean") { return .yellow }
        if v.contains("deadlock") { return .red }
        return .secondary
    }

    var relativeTime: String {
        guard let dateStr = createdAt else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr)
                ?? ISO8601DateFormatter().date(from: dateStr) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - API Responses

struct PostListResponse: Codable {
    let posts: [Post]
    let count: Int?
    let restricted: Bool?
}

struct PostDetailResponse: Codable {
    let post: Post
    let positions: [Position]?
    let votes: [VoteItem]?
}

struct Position: Codable, Identifiable {
    let dbId: Int?
    let postId: String?
    let round: Int
    let agentSlug: String
    let agentDomain: String?
    let position: String
    let confidence: Double?
    let reasoning: String?
    let changed: Bool?

    var id: String { "\(postId ?? "")-\(round)-\(agentSlug)" }

    enum CodingKeys: String, CodingKey {
        case round, position, confidence, reasoning, changed
        case dbId = "id"
        case postId = "post_id"
        case agentSlug = "agent_slug"
        case agentDomain = "agent_domain"
    }

    var positionIcon: String {
        switch position.lowercased() {
        case "bullish", "agree", "support": return "arrow.up.circle.fill"
        case "bearish", "disagree", "oppose": return "arrow.down.circle.fill"
        case "neutral", "abstain": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    var positionColor: Color {
        switch position.lowercased() {
        case "bullish", "agree", "support": return .green
        case "bearish", "disagree", "oppose": return .red
        case "neutral", "abstain": return .yellow
        default: return .gray
        }
    }
}

struct VoteItem: Codable, Identifiable {
    let dbId: Int?
    let postId: String?
    let position: String
    let weightedScore: Double?
    let voteCount: Int?

    var id: String { "\(postId ?? "")-\(position)" }

    enum CodingKeys: String, CodingKey {
        case position
        case dbId = "id"
        case postId = "post_id"
        case weightedScore = "weighted_score"
        case voteCount = "vote_count"
    }

    var voteColor: String {
        switch position.lowercased() {
        case "support", "bullish", "agree": return "green"
        case "oppose", "bearish", "disagree": return "red"
        default: return "yellow"
        }
    }
}

// MARK: - Board Definition

struct Board: Identifiable {
    let id: String
    let name: String
    let icon: String      // SF Symbol name
    let restricted: Bool

    static let all: [Board] = [
        Board(id: "all", name: "All Posts", icon: "square.grid.2x2.fill", restricted: false),
        Board(id: "prediction", name: "Prediction", icon: "chart.line.uptrend.xyaxis.circle.fill", restricted: false),
        Board(id: "cross", name: "Cross Domain", icon: "globe", restricted: false),
        Board(id: "spiritual", name: "Spiritual", icon: "cross.fill", restricted: false),
        Board(id: "board", name: "Board Room", icon: "building.columns.fill", restricted: false),
        Board(id: "tcm", name: "TCM Clinic", icon: "leaf.fill", restricted: false),
        Board(id: "digest", name: "Daily Digest", icon: "newspaper.fill", restricted: false),
        Board(id: "research", name: "Research Lab", icon: "microscope.fill", restricted: true),
        Board(id: "quant", name: "Trading Desk", icon: "chart.line.uptrend.xyaxis", restricted: true),
        Board(id: "intel", name: "Intel Vault", icon: "lock.shield.fill", restricted: true),
    ]

    static let publicBoards: [Board] = all.filter { !$0.restricted }
    static let proBoards: [Board] = all.filter { $0.restricted }
}
