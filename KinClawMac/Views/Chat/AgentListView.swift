import SwiftUI

struct AgentListView: View {
    @EnvironmentObject var appState: AppState
    @State private var agents: [Agent] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var errorMessage: String?

    var filteredAgents: [Agent] {
        let online = agents.filter { $0.online }
        if searchText.isEmpty { return online }
        return online.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.slug.localizedCaseInsensitiveContains(searchText) ||
            ($0.domain ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var groupedAgents: [(String, [Agent])] {
        let grouped = Dictionary(grouping: filteredAgents) { $0.domain ?? "other" }
        return grouped
            .map { domain, agents in
                let sorted = agents.sorted { a, b in
                    let aIsConductor = a.slug.contains("conductor")
                    let bIsConductor = b.slug.contains("conductor")
                    if aIsConductor != bIsConductor { return aIsConductor }
                    return a.displayName < b.displayName
                }
                return (domain, sorted)
            }
            .sorted { a, b in
                if a.0 == "core" { return true }
                if b.0 == "core" { return false }
                return a.0 < b.0
            }
    }

    var domainCount: Int {
        Set(filteredAgents.compactMap { $0.domain }).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Discovering agents...")
                        .tint(.green)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") { Task { await loadAgents() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                    }
                } else if filteredAgents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No agents found")
                            .foregroundColor(.secondary)
                    }
                } else {
                    agentGrid
                }
            }
            .navigationTitle("Choose Your Agent")
            .largeNavTitle()
            .searchable(text: $searchText, prompt: "Search agents...")
            .refreshable { await loadAgents() }
            .task { await loadAgents() }
            .toolbar {
                ToolbarItem(placement: .trailingAction) {
                    Text(appState.remainingDisplay)
                        .font(.caption)
                        .foregroundColor(appState.isPro ? .green : appState.isInTrial ? .blue : .secondary)
                }
            }
        }
    }

    // MARK: - Agent Grid

    private var agentGrid: some View {
        ScrollView {
            HStack {
                Text("\(filteredAgents.count) agents online")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\u{00B7}")
                    .foregroundColor(.secondary)
                Text("\(domainCount) domains")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)

            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groupedAgents, id: \.0) { domain, domainAgents in
                    VStack(alignment: .leading, spacing: 12) {
                        domainHeader(domain, count: domainAgents.count)

                        let columns = [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(domainAgents) { agent in
                                NavigationLink(destination: ChatView(agent: agent)) {
                                    agentCard(agent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    private func domainHeader(_ domain: String, count: Int) -> some View {
        let icon = Self.domainIcon(domain)
        let color = Self.domainColor(domain)
        let label = domain.replacingOccurrences(of: "_", with: " ").uppercased()
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func agentCard(_ agent: Agent) -> some View {
        let isConductor = agent.slug.contains("conductor")
        let icon = Self.agentIcon(agent.slug, domain: agent.domain ?? "")
        let color = Self.domainColor(agent.domain ?? "")

        return VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(isConductor ? .green : color)
                .frame(height: 44)

            Text(agent.displayName)
                .font(.system(size: 11))
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Color.platformSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isConductor ? Color.green.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - SF Symbol Mappings

    static func domainIcon(_ domain: String) -> String {
        switch domain {
        case "core": return "star.fill"
        case "board": return "building.columns.fill"
        case "bible": return "book.fill"
        case "csuite": return "person.crop.rectangle.fill"
        case "design": return "paintbrush.fill"
        case "engineering": return "gearshape.2.fill"
        case "game_dev": return "gamecontroller.fill"
        case "integration": return "link"
        case "marketing": return "megaphone.fill"
        case "paid_media": return "dollarsign.circle.fill"
        case "prediction": return "crystal.ball.fill"
        case "product": return "shippingbox.fill"
        case "project_management": return "list.clipboard.fill"
        case "qa": return "checkmark.shield.fill"
        case "quant": return "chart.line.uptrend.xyaxis"
        case "spatial_computing": return "visionpro.fill"
        case "specialist": return "microscope.fill"
        case "spiritual": return "cross.fill"
        case "support": return "lifepreserver.fill"
        case "tcm": return "leaf.fill"
        default: return "cpu.fill"
        }
    }

    static func domainColor(_ domain: String) -> Color {
        switch domain {
        case "core": return .yellow
        case "board": return .blue
        case "bible": return .orange
        case "csuite": return .purple
        case "design": return .pink
        case "engineering": return .cyan
        case "game_dev": return .red
        case "integration": return .teal
        case "marketing": return .orange
        case "paid_media": return .green
        case "prediction": return .purple
        case "product": return .indigo
        case "project_management": return .blue
        case "qa": return .mint
        case "quant": return .green
        case "spatial_computing": return .cyan
        case "specialist": return .teal
        case "spiritual": return .yellow
        case "support": return .orange
        case "tcm": return .green
        default: return .gray
        }
    }

    static func agentIcon(_ slug: String, domain: String) -> String {
        // Per-agent icons
        switch slug {
        // Core
        case "english": return "book.fill"
        case "tcm": return "leaf.fill"
        case "guyon": return "sparkles"
        case "citizen": return "building.columns.fill"
        case "spanish": return "globe.americas.fill"
        case "house": return "house.fill"
        case "scout-web": return "binoculars.fill"
        case "travel_rescue": return "airplane"
        // Board
        case "board_conductor": return "target"
        case "board_ceo": return "person.fill"
        case "board_cfo": return "dollarsign.circle.fill"
        case "board_cto": return "desktopcomputer"
        case "board_growth": return "arrow.up.right"
        case "board_intel": return "eye.fill"
        // Bible
        case "bezalel": return "paintbrush.pointed.fill"
        case "nehemiah": return "hammer.fill"
        case "paul": return "envelope.fill"
        // C-Suite
        case "ceo": return "person.fill"
        case "cfo": return "dollarsign.circle.fill"
        case "growth": return "arrow.up.right"
        case "intel": return "eye.fill"
        // Design
        case "brand_guardian": return "shield.fill"
        case "image_prompt_engineer": return "photo.fill"
        case "inclusive_visuals": return "figure.2.arms.open"
        case "ui_designer": return "iphone"
        case "ux_architect": return "rectangle.3.group.fill"
        case "ux_researcher": return "magnifyingglass"
        case "visual_storyteller": return "camera.fill"
        case "whimsy_injector": return "wand.and.stars"
        // Engineering
        case "ai_data_remediation": return "wrench.fill"
        case "ai_engineer": return "cpu.fill"
        case "autonomous_optimization": return "arrow.triangle.2.circlepath"
        case "backend_architect": return "server.rack"
        case "code_reviewer": return "magnifyingglass"
        case "data_engineer": return "cylinder.fill"
        case "db_optimizer": return "cylinder.fill"
        case "devops": return "terminal.fill"
        case "embedded_firmware": return "memorychip.fill"
        case "feishu_dev": return "bubble.left.fill"
        case "frontend_dev": return "paintbrush.fill"
        case "git_workflow": return "arrow.triangle.branch"
        case "incident_commander": return "exclamationmark.triangle.fill"
        case "mobile_builder": return "iphone"
        case "rapid_prototyper": return "bolt.fill"
        case "security_engineer": return "lock.fill"
        case "senior_dev": return "chevron.left.forwardslash.chevron.right"
        case "software_architect": return "building.2.fill"
        case "solidity_dev": return "link"
        case "sre": return "chart.bar.fill"
        case "technical_writer": return "doc.text.fill"
        case "threat_detection": return "shield.lefthalf.filled"
        case "wechat_miniprogram": return "message.fill"
        // Game Dev
        case "game_artist": return "paintpalette.fill"
        case "game_audio": return "speaker.wave.3.fill"
        case "game_designer": return "gamecontroller.fill"
        case "game_economist": return "banknote.fill"
        case "narrative_designer": return "text.book.closed.fill"
        // Integration
        case "api_integrator": return "link"
        // Marketing
        case "app_store_optimizer": return "arrow.down.app.fill"
        case "baidu_seo": return "magnifyingglass"
        case "bilibili_strategist": return "play.rectangle.fill"
        case "book_coauthor": return "books.vertical.fill"
        case "carousel_growth": return "rectangle.stack.fill"
        case "content_creator": return "pencil"
        case "content_strategist_cn": return "doc.richtext.fill"
        case "cross_border_ecom": return "globe"
        case "douyin_strategist": return "music.note"
        case "growth_hacker": return "chart.line.uptrend.xyaxis"
        case "instagram_strategist": return "camera.fill"
        case "kuaishou_strategist": return "bolt.fill"
        case "linkedin_strategist": return "briefcase.fill"
        case "livestream_coach": return "video.fill"
        case "podcast_strategist": return "mic.fill"
        case "private_domain": return "lock.fill"
        case "reddit_strategist": return "bubble.left.and.bubble.right.fill"
        case "seo_specialist": return "magnifyingglass"
        case "short_video_coach": return "film"
        case "social_media_strategist": return "iphone"
        case "tiktok_strategist": return "music.note"
        case "twitter_strategist": return "at"
        case "wechat_official": return "message.fill"
        case "weibo_strategist": return "globe.asia.australia.fill"
        case "xiaohongshu_strategist": return "heart.text.square.fill"
        case "zhihu_strategist": return "questionmark.circle.fill"
        // Paid Media
        case "creative_strategist": return "lightbulb.fill"
        case "google_ads": return "magnifyingglass"
        case "linkedin_ads": return "briefcase.fill"
        case "media_buyer": return "cart.fill"
        case "meta_ads": return "m.circle.fill"
        case "programmatic": return "cpu.fill"
        case "tiktok_ads": return "music.note"
        // Product
        case "behavioral_nudge": return "brain.head.profile.fill"
        case "feedback_synthesizer": return "chart.bar.fill"
        case "sprint_prioritizer": return "flag.fill"
        case "trend_researcher": return "chart.line.uptrend.xyaxis"
        // Project Management
        case "experiment_tracker": return "flask.fill"
        case "jira_steward": return "list.clipboard.fill"
        case "project_shepherd": return "person.fill.checkmark"
        case "senior_pm": return "chart.bar.doc.horizontal.fill"
        case "studio_ops": return "film.fill"
        case "studio_producer": return "play.circle.fill"
        // QA
        case "accessibility_auditor": return "accessibility.fill"
        case "api_tester": return "checkmark.circle.fill"
        case "evidence_collector": return "doc.text.magnifyingglass"
        case "performance_benchmarker": return "speedometer"
        case "reality_checker": return "checkmark.seal.fill"
        case "test_analyzer": return "chart.bar.fill"
        case "tool_evaluator": return "hammer.fill"
        case "workflow_optimizer": return "arrow.triangle.2.circlepath"
        // Quant
        case "oracle": return "eye.trianglebadge.exclamationmark.fill"
        case "quant": return "chart.line.uptrend.xyaxis"
        case "trader": return "chart.bar.fill"
        // Spatial Computing
        case "metal_engineer": return "gpu.fill"
        case "simulation_engineer": return "cube.transparent.fill"
        case "spatial_audio": return "hifispeaker.2.fill"
        case "spatial_engineer": return "visionpro.fill"
        case "visionos_engineer": return "eye.circle.fill"
        case "xr_architect": return "view.3d"
        // Specialist
        case "accounts_payable": return "creditcard.fill"
        case "agents_orchestrator": return "person.3.fill"
        case "blockchain_auditor": return "link"
        case "change_manager": return "arrow.2.squarepath"
        case "competitive_intel": return "eye.fill"
        case "compliance_auditor": return "checkmark.shield.fill"
        case "crisis_manager": return "exclamationmark.triangle.fill"
        case "cultural_intelligence": return "globe"
        case "customer_insights": return "person.fill.questionmark"
        case "data_consolidation": return "rectangle.stack.fill"
        case "data_scientist": return "microscope.fill"
        case "developer_advocate": return "megaphone.fill"
        case "document_generator": return "doc.fill"
        case "ethics_advisor": return "scale.3d"
        case "governance_architect": return "building.columns.fill"
        case "government_presales": return "building.fill"
        case "healthcare_compliance": return "cross.case.fill"
        case "mcp_builder": return "wrench.and.screwdriver.fill"
        case "patent_analyst": return "scroll.fill"
        case "prediction_conductor": return "target"
        case "pricing_strategist": return "tag.fill"
        case "prompt_engineer": return "text.cursor"
        case "sustainability_advisor": return "leaf.fill"
        case "training_designer": return "graduationcap.fill"
        // Spiritual
        case "cloud_author": return "cloud.fill"
        case "interpreter": return "book.fill"
        case "john_cross": return "cross.fill"
        case "lawrence": return "hands.and.sparkles.fill"
        case "molinos": return "wind"
        case "murray": return "book.closed.fill"
        case "s_guyon": return "sparkles"
        case "spiritual_conductor": return "target"
        case "teresa_avila": return "building.columns.fill"
        case "therese": return "heart.fill"
        // Support
        case "analytics_reporter": return "chart.bar.fill"
        case "executive_summary": return "doc.plaintext.fill"
        case "finance_tracker": return "dollarsign.circle.fill"
        case "infra_maintainer": return "wrench.fill"
        case "legal_compliance": return "scale.3d"
        case "support_responder": return "headphones"
        // TCM
        case "hua_tuo": return "cross.case.fill"
        case "huangfu_mi": return "mappin.and.ellipse"
        case "sun_simiao": return "leaf.fill"
        case "tcm_conductor": return "target"
        case "zhang_zhongjing": return "scroll.fill"
        default:
            // Fallback: domain-based icon
            return domainIcon(domain)
        }
    }

    // MARK: - Data

    private func loadAgents() async {
        isLoading = agents.isEmpty
        errorMessage = nil
        do {
            agents = try await APIClient.shared.fetchAgents()
        } catch {
            if agents.isEmpty {
                errorMessage = "Could not reach api.localkin.dev"
            }
        }
        isLoading = false
    }
}
