import SwiftUI

struct PostDetailView: View {
    let postId: String
    @EnvironmentObject var appState: AppState
    @State private var post: Post?
    @State private var positions: [Position] = []
    @State private var votes: [VoteItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expandedPositions: Set<String> = []

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 100)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 100)
            } else if let post = post {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    postHeader(post)

                    Divider()

                    // Content based on type
                    switch post.type {
                    case "article":
                        articleContent(post)
                    case "debate":
                        debateContent(post)
                    default:
                        if let detail = post.verdictDetail {
                            Text(detail)
                                .font(.body)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.platformBackground)
        .compactNavTitle()
        .task { await loadPost() }
    }

    // MARK: - Header

    private func postHeader(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type + Board
            HStack {
                Text(post.displayType)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor(post).opacity(0.15))
                    .foregroundColor(badgeColor(post))
                    .clipShape(Capsule())

                if let board = post.board,
                   let boardDef = Board.all.first(where: { $0.id == board }) {
                    Label(boardDef.name, systemImage: boardDef.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(post.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Title
            Text(post.topic ?? "Untitled")
                .font(.title2)
                .fontWeight(.bold)

            // Conductor + stats
            HStack {
                if let conductor = post.conductor {
                    Label(conductor.replacingOccurrences(of: "_", with: " "),
                          systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let p = post.participants, p > 0 {
                    Label("\(p) agents", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let r = post.roundsCompleted, r > 0 {
                    Label("\(r) rounds", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Article Content

    private func articleContent(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let content = post.verdictDetail {
                Text(LocalizedStringKey(content))
                    .font(.body)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Debate Content

    private func debateContent(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Verdict card
            if let verdict = post.verdict {
                HStack(spacing: 12) {
                    Image(systemName: post.verdictIcon)
                        .font(.title)
                        .foregroundColor(post.verdictColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict)
                            .font(.headline)
                        if let ratio = post.consensusRatio {
                            Text("\(Int(ratio * 100))% consensus")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(Color.platformSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Vote breakdown
            if !votes.isEmpty {
                voteBreakdown(votes)
            }

            // Summary (the full board meeting minutes)
            if let summary = post.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Summary", systemImage: "doc.text.fill")
                        .font(.headline)
                    Text(LocalizedStringKey(summary))
                        .font(.body)
                        .lineSpacing(4)
                }
            }

            // Short verdict detail (if different from summary)
            if let detail = post.verdictDetail,
               post.summary == nil || post.summary?.isEmpty == true {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Analysis", systemImage: "text.magnifyingglass")
                        .font(.headline)
                    Text(LocalizedStringKey(detail))
                        .font(.body)
                        .lineSpacing(4)
                }
            }

            // Positions by round
            if !positions.isEmpty {
                positionsSection
            }
        }
    }

    // MARK: - Vote Breakdown

    private func voteBreakdown(_ votes: [VoteItem]) -> some View {
        let total = votes.compactMap(\.voteCount).reduce(0, +)
        return HStack(spacing: 0) {
            ForEach(votes) { vote in
                let color: Color = {
                    switch vote.position.lowercased() {
                    case "support", "bullish", "agree": return .green
                    case "oppose", "bearish", "disagree": return .red
                    default: return .yellow
                    }
                }()
                VStack(spacing: 2) {
                    Text("\(vote.voteCount ?? 0)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(vote.position.capitalized)
                        .font(.caption2)
                    if total > 0, let vc = vote.voteCount {
                        Text("\(Int(Double(vc) / Double(total) * 100))%")
                            .font(.system(size: 9))
                            .foregroundColor(color.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.15))
                .foregroundColor(color)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Positions

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent Positions", systemImage: "person.3.sequence.fill")
                .font(.headline)

            let rounds = Dictionary(grouping: positions) { $0.round }
            ForEach(rounds.keys.sorted(), id: \.self) { round in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round \(round)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(rounds[round] ?? []) { position in
                        positionRow(position)
                    }
                }
            }
        }
    }

    private func positionRow(_ position: Position) -> some View {
        let isExpanded = expandedPositions.contains(position.id)

        return VStack(alignment: .leading, spacing: 6) {
            // Header row - tappable
            HStack {
                Image(systemName: position.positionIcon)
                    .foregroundColor(position.positionColor)
                Text(position.agentSlug.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let conf = position.confidence {
                    Text("\(Int(conf * 100))%")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.platformTertiaryBackground)
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                }
                if position.changed == true {
                    Text("FLIPPED")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Reasoning - expandable
            if let reasoning = position.reasoning, !reasoning.isEmpty {
                if isExpanded {
                    Text(LocalizedStringKey(reasoning))
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.top, 4)
                } else {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(Color.platformSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedPositions.remove(position.id)
                } else {
                    expandedPositions.insert(position.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func badgeColor(_ post: Post) -> Color {
        switch post.type {
        case "debate": return .purple
        case "article": return .blue
        case "briefing": return .orange
        default: return .gray
        }
    }

    private func loadPost() async {
        isLoading = true
        do {
            let token = appState.isPro ? appState.licenseKey : nil
            let response = try await APIClient.shared.fetchPost(id: postId, token: token)
            post = response.post
            positions = response.positions ?? []
            votes = response.votes ?? []
        } catch {
            errorMessage = "Could not load post"
        }
        isLoading = false
    }
}
