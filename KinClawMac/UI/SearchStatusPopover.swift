import SwiftUI
import AppKit

/// Search-health indicator for Cowork: a magnifier with a status dot in
/// the agent bar, and a popover with the last real search (backend,
/// engines that answered, engines that were down and why) plus an
/// on-demand probe of the major engines. Reads the kernel's
/// /api/search/status and /api/search/probe — the probe is one
/// restricted search, only when you click, never on a timer.
@MainActor
final class SearchStatusStore: ObservableObject {
    struct EngineDown: Decodable, Identifiable {
        let name: String
        let reason: String
        var id: String { name }
    }
    struct Last: Decodable {
        let time: String?
        let query: String?
        let backend: String?
        let results: Int?
        let engines: [String: Int]?
        let unresponsive: [EngineDown]?
        let error: String?
    }
    struct Status: Decodable {
        let endpoint: String?
        let last: Last?
    }
    struct EngineProbe: Decodable, Identifiable {
        let name: String
        let enabled: Bool
        let status: String   // ok | down | empty | disabled | untested
        let reason: String?
        let results: Int
        var id: String { name }
    }
    struct Probe: Decodable {
        let endpoint: String
        let reachable: Bool
        let version: String?
        let error: String?
        let engines: [EngineProbe]
        let healthy: Int
    }

    @Published private(set) var status: Status?
    @Published private(set) var probe: Probe?
    @Published private(set) var probing = false
    @Published private(set) var fetchFailed = false

    private let base = URL(string: "http://localhost:5001")!

    /// Traffic-light colour for the bar icon.
    var dotColor: Color {
        if let p = probe {
            if !p.reachable { return .red }
            return p.healthy >= 2 ? .green : (p.healthy == 1 ? .yellow : .orange)
        }
        guard let last = status?.last else {
            return status?.endpoint?.isEmpty == false ? .gray : .gray.opacity(0.5)
        }
        if last.error != nil { return .red }
        let down = last.unresponsive?.count ?? 0
        if down == 0 { return .green }
        return down >= 3 ? .orange : .yellow
    }

    func refresh() async {
        do {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/search/status"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { fetchFailed = true; return }
            status = try JSONDecoder().decode(Status.self, from: data)
            fetchFailed = false
        } catch {
            fetchFailed = true
        }
    }

    func runProbe() async {
        probing = true
        defer { probing = false }
        var req = URLRequest(url: base.appendingPathComponent("api/search/probe"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            probe = try JSONDecoder().decode(Probe.self, from: data)
        } catch {
            // Leave the previous probe; the dot keeps its last colour.
        }
    }
}

struct SearchStatusButton: View {
    @ObservedObject var store: SearchStatusStore
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
            if showing { Task { await store.refresh() } }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Circle()
                    .fill(store.dotColor)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Search engines — what the last web_search actually got, and a health probe")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            SearchStatusPopover(store: store)
        }
        .task { await store.refresh() }
    }
}

struct SearchStatusPopover: View {
    @ObservedObject var store: SearchStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search engines")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let ep = store.status?.endpoint, !ep.isEmpty {
                    Button("Open SearXNG") {
                        if let u = URL(string: ep) { NSWorkspace.shared.open(u) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                }
            }

            lastSection
            Divider().opacity(0.2)
            probeSection
        }
        .padding(12)
        .frame(width: 340)
    }

    @ViewBuilder
    private var lastSection: some View {
        if let ep = store.status?.endpoint, ep.isEmpty {
            Text("No SEARXNG_ENDPOINT — web_search falls back to the DuckDuckGo HTML scrape, which this IP is currently blocked from.")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        if let last = store.status?.last {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last search").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                if let q = last.query {
                    Text("“\(q)”").font(.system(size: 11)).lineLimit(2)
                }
                if let e = last.error {
                    Text(e).font(.system(size: 10)).foregroundColor(.red)
                } else {
                    Text("\(last.results ?? 0) results via \(last.backend ?? "?") · from \(engineList(last.engines))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let down = last.unresponsive, !down.isEmpty {
                    ForEach(down) { d in
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                            Text("\(d.name) — \(d.reason)").font(.system(size: 10))
                        }
                    }
                }
                if let t = last.time, let d = ISO8601DateFormatter.flexible.date(from: t) {
                    Text(RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date()))
                        .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.7))
                }
            }
        } else if store.fetchFailed {
            Text("kinclaw not reachable on :5001").font(.system(size: 10)).foregroundColor(.orange)
        } else {
            Text("No search yet this session.").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var probeSection: some View {
        HStack {
            Text("Engine health").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            Spacer()
            Button(store.probing ? "Probing…" : "Probe now") {
                Task { await store.runProbe() }
            }
            .controlSize(.small)
            .disabled(store.probing)
            .help("One search restricted to the major engines — never runs on a timer")
        }
        if let p = store.probe {
            if !p.reachable {
                Text(p.error ?? "unreachable").font(.system(size: 10)).foregroundColor(.red)
            } else {
                ForEach(p.engines) { e in
                    HStack(spacing: 6) {
                        Circle().fill(color(e.status)).frame(width: 6, height: 6)
                        Text(e.name).font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text(label(e)).font(.system(size: 10)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                if let v = p.version {
                    Text("SearXNG \(v) · \(p.healthy) major engine(s) answering")
                        .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.7))
                }
                if p.healthy < 2 {
                    Text("Weak: enable google in settings.yml, update the searxng image, and keep the watchdog off real searches — see kinclaw CHANGELOG.")
                        .font(.system(size: 9)).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func engineList(_ m: [String: Int]?) -> String {
        guard let m = m, !m.isEmpty else { return "?" }
        return m.keys.sorted().joined(separator: ", ")
    }
    private func color(_ status: String) -> Color {
        switch status {
        case "ok": return .green
        case "down": return .red
        case "empty": return .yellow
        case "disabled": return .gray
        default: return .gray.opacity(0.4)
        }
    }
    private func label(_ e: SearchStatusStore.EngineProbe) -> String {
        switch e.status {
        case "ok": return "\(e.results) results"
        case "down": return e.reason ?? "down"
        case "empty": return "no results"
        case "disabled": return "disabled in settings.yml"
        default: return e.reason ?? "untested"
        }
    }
}

private extension ISO8601DateFormatter {
    /// Go's RFC3339Nano timestamps carry fractional seconds.
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
