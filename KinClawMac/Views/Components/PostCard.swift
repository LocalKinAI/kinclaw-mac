import SwiftUI

struct PostCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type badge + time
            HStack {
                typeBadge
                Spacer()
                Text(post.relativeTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Topic
            Text(post.topic ?? "Untitled")
                .font(.headline)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Metadata
            HStack(spacing: 16) {
                if post.type == "debate" {
                    debateMetadata
                } else if post.type == "article" {
                    articleMetadata
                }
            }

            // Verdict bar for debates
            if post.type == "debate", let ratio = post.consensusRatio {
                consensusBar(ratio: ratio)
            }
        }
        .padding()
        .background(Color.platformSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        HStack(spacing: 4) {
            if post.type == "debate" {
                Image(systemName: post.verdictIcon)
                    .font(.caption2)
                    .foregroundColor(post.verdictColor)
            }
            Text(post.displayType)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .foregroundColor(badgeColor)
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch post.type {
        case "debate": return .purple
        case "article": return .blue
        case "briefing": return .orange
        default: return .gray
        }
    }

    // MARK: - Metadata

    private var debateMetadata: some View {
        Group {
            Label("\(post.participants ?? 0)", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            Label("\(post.roundsCompleted ?? 0)R", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundColor(.secondary)
            if let changes = post.positionChanges, changes > 0 {
                Label("\(changes) flips", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var articleMetadata: some View {
        Group {
            if let conductor = post.conductor {
                Label(conductor.replacingOccurrences(of: "_", with: " "),
                      systemImage: "person.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let board = post.board {
                let boardDef = Board.all.first { $0.id == board }
                Label(boardDef?.name ?? board, systemImage: boardDef?.icon ?? "doc.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Consensus Bar

    private func consensusBar(ratio: Double) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.3))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(ratio * 100))% consensus")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(post.verdict ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
}
