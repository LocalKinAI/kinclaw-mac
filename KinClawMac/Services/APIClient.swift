import Foundation

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Agent Discovery

    /// Fetch all online agents from api.localkin.dev
    func fetchAgents() async throws -> [Agent] {
        let url = URL(string: "https://api.localkin.dev/v1/agents")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode([Agent].self, from: data)
    }

    /// Check health of a specific agent
    func healthCheck(hostname: String) async throws -> AgentHealthResponse {
        let url = URL(string: "https://\(hostname)/v1/health")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(AgentHealthResponse.self, from: data)
    }

    // MARK: - Chat (Non-Streaming)

    func sendMessage(
        to hostname: String,
        messages: [APIMessage],
        token: String? = nil
    ) async throws -> String {
        let url = URL(string: "https://\(hostname)/v1/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(messages: messages, stream: false, noHistory: true)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ChatResponse.self, from: data)
        return response.choices?.first?.message?.content ?? ""
    }

    // MARK: - KinBook

    /// Fetch posts from KinBook
    func fetchPosts(
        board: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        token: String? = nil
    ) async throws -> PostListResponse {
        var components = URLComponents(string: "https://www.localkin.dev/api/kinbook/debates")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "sort", value: "latest"),
        ]
        if let board = board, board != "all" {
            queryItems.append(URLQueryItem(name: "board", value: board))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: request)
        return try decoder.decode(PostListResponse.self, from: data)
    }

    /// Fetch single post detail
    func fetchPost(id: String, token: String? = nil) async throws -> PostDetailResponse {
        let url = URL(string: "https://www.localkin.dev/api/kinbook/debates/\(id)")!
        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await session.data(for: request)
        return try decoder.decode(PostDetailResponse.self, from: data)
    }

    /// Fetch fleet status (online agent count)
    func fetchFleetCount() async throws -> Int {
        let url = URL(string: "https://www.localkin.dev/api/fleet")!
        let (data, _) = try await session.data(from: url)
        struct FleetResponse: Codable { let online: Int }
        let response = try decoder.decode(FleetResponse.self, from: data)
        return response.online
    }
}
