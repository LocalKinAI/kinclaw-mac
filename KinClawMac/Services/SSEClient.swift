import Foundation

// MARK: - Server-Sent Events Client for Streaming Chat

class SSEClient: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = ""

    var onToken: ((String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((Error) -> Void)?

    /// `agentSlug` is required for the cloud gateway — chat is now
    /// addressed by `?agent=<slug>` query parameter rather than
    /// per-agent hostnames. See `selah-chat.ts` in localkin-player
    /// for the canonical reference. Pass `nil` only when you have
    /// upgraded an old call site and a slug isn't available yet
    /// (the cloud will reject the request, surfacing the gap).
    func startStreaming(
        hostname: String,
        agentSlug: String?,
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
            self.beginRequest(hostname: hostname,
                              agentSlug: agentSlug,
                              messages: messages,
                              authToken: authToken)
        }
    }

    private func beginRequest(hostname: String, agentSlug: String?,
                              messages: [APIMessage], authToken: String) {
        // 2026-04: cloud gateway switched to single endpoint with
        // `?agent=<slug>` selector. Older /v1/chat without the
        // selector returns 404. We URL-encode defensively even
        // though slugs are always plain ASCII underscores today.
        var components = URLComponents(string: "https://\(hostname)/v1/chat")!
        if let slug = agentSlug, !slug.isEmpty {
            components.queryItems = [URLQueryItem(name: "agent", value: slug)]
        }
        let url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        // X-Lang lets the gateway pick the right localized greeting
        // / refusal message. Read user's pref from UserDefaults
        // (set in Settings > General > Language). "auto" → match
        // the current macOS locale.
        request.setValue(resolvedLang(), forHTTPHeaderField: "X-Lang")

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

    /// Resolves the X-Lang header value from the user's Settings
    /// preference. "auto" → current macOS locale's language code
    /// (zh-Hans → "zh", en-US → "en"); explicit zh/en passes
    /// through. Falls back to "zh" since the LocalKin masters lean
    /// Chinese-first.
    private func resolvedLang() -> String {
        let pref = UserDefaults.standard.string(forKey: "kinclaw.lang") ?? "auto"
        if pref == "zh" || pref == "en" { return pref }
        let locale = Locale.current.language.languageCode?.identifier ?? "zh"
        return locale.hasPrefix("zh") ? "zh" : "en"
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
