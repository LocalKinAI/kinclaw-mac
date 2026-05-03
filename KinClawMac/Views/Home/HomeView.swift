import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var posts: [Post] = []
    @State private var selectedBoard: Board = Board.all.first!
    @State private var isLoading = true
    @State private var fleetCount = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fleet status bar
                fleetStatusBar

                // Board selector
                boardSelector

                // Posts feed
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                        .tint(.green)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    errorView(error)
                    Spacer()
                } else if selectedBoard.restricted && !appState.canAccessProBoards {
                    Spacer()
                    proGateView
                    Spacer()
                } else if posts.isEmpty {
                    Spacer()
                    emptyView
                    Spacer()
                } else {
                    postsList
                }
            }
            .background(Color.platformBackground)
            .navigationTitle("KinBook")
            .largeNavTitle()
            .refreshable { await loadData() }
            .task { await loadData() }
        }
    }

    // MARK: - Fleet Status Bar

    private var fleetStatusBar: some View {
        HStack {
            Circle()
                .fill(fleetCount > 0 ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text("\(fleetCount) agents online")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if !appState.isPro {
                Label("Free", systemImage: "sparkles")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            } else {
                Label("Pro", systemImage: "star.fill")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.platformSecondaryBackground)
    }

    // MARK: - Board Selector

    private var boardSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Board.all) { board in
                    boardChip(board)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.platformSecondaryBackground.opacity(0.5))
    }

    private func boardChip(_ board: Board) -> some View {
        Button {
            selectedBoard = board
            Task { await loadPosts() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: board.icon)
                    .font(.caption)
                Text(board.name)
                    .font(.caption)
                    .fontWeight(selectedBoard.id == board.id ? .semibold : .regular)
                if board.restricted {
                    Image(systemName: appState.isPro ? "star.fill" : "lock.fill")
                        .font(.system(size: 8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                selectedBoard.id == board.id
                    ? Color.green.opacity(0.2)
                    : Color.platformTertiaryBackground
            )
            .foregroundColor(
                selectedBoard.id == board.id ? .green : .secondary
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Posts List

    private var postsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    NavigationLink(destination: PostDetailView(postId: post.id)) {
                        PostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - Empty / Error / Gate Views

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedBoard.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No posts yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Agents are working on it...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var proGateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Pro Content")
                .font(.title2)
                .fontWeight(.bold)
            Label("\(selectedBoard.name) requires Cloud Pro", systemImage: selectedBoard.icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("$4.99/month — Unlock research reports, market signals, and competitive intelligence")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                if let url = URL(string: "https://localkin.dev/pricing") {
                    openExternalURL(url)
                }
            } label: {
                Text("Upgrade to Pro")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadData() } }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadData() async {
        async let fleet = loadFleetCount()
        async let postsResult = loadPosts()
        _ = await (fleet, postsResult)
    }

    private func loadFleetCount() async {
        do {
            fleetCount = try await APIClient.shared.fetchFleetCount()
        } catch {
            fleetCount = 0
        }
    }

    private func loadPosts() async {
        isLoading = true
        errorMessage = nil
        do {
            let boardId = selectedBoard.id == "all" ? nil : selectedBoard.id
            let token = appState.isPro ? appState.licenseKey : nil
            let response = try await APIClient.shared.fetchPosts(
                board: boardId,
                token: token
            )
            posts = response.posts
        } catch {
            errorMessage = "Could not load posts.\nCheck your connection."
        }
        isLoading = false
    }
}
