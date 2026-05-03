import Foundation

// MARK: - Server-Sent Events Client for Streaming Chat

class SSEClient: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = ""

    var onToken: ((String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((Error) -> Void)?

    func startStreaming(
        hostname: String,
        messages: [APIMessage],
        token: String? = nil
    ) {
        // Get token from TokenManager (async) then start request
        Task { @MainActor in
            let authToken: String
            if let t = token {
                authToken = t
            } else {
                authToken = await TokenManager.shared.token(for: hostname)
            }
            self.beginRequest(hostname: hostname, messages: messages, authToken: authToken)
        }
    }

    private func beginRequest(hostname: String, messages: [APIMessage], authToken: String) {
        let url = URL(string: "https://\(hostname)/v1/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(messages: messages, stream: true, noHistory: true)
        request.httpBody = try? JSONEncoder().encode(body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        task = session?.dataTask(with: request)
        buffer = ""
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process complete SSE lines
        while let range = buffer.range(of: "\n\n") {
            let event = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            for line in event.components(separatedBy: "\n") {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))

                if payload == "[DONE]" {
                    onComplete?()
                    return
                }

                guard let jsonData = payload.data(using: .utf8),
                      let response = try? JSONDecoder().decode(ChatResponse.self, from: jsonData),
                      let delta = response.choices?.first?.delta,
                      let content = delta.content else {
                    continue
                }

                onToken?(content)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            onError?(error)
        }
        // Process any remaining buffer
        if !buffer.isEmpty {
            onComplete?()
        }
    }
}
