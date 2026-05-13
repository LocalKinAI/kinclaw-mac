import SwiftUI

// MARK: - StudioView
//
// The 4th tab — "Studio" — for self-hosted private workflows.
//
// Architectural shape: open-core at solo-founder scale. KinClaw Mac is
// Apache 2.0 (the shell, the agents tab, the kinbook reader, the
// settings — all in this public repo). Studio is a UI frame for
// private souls that live in a *sibling* repo (`localkin` family-
// private repo, optional). If the user has the sibling on disk, their
// private souls show up as cards here; if not, this tab renders an
// empty state explaining how to populate it.
//
// Public-clone UX:
//   - User clones LocalKinAI/kinclaw-mac, runs `make`.
//   - Studio tab appears (always) with "No private souls detected"
//     and a copyable path to drop their own souls into.
//   - User creates a sibling `localkin/souls/private/foo.soul.md`
//     manually, re-launches → Studio tab shows their soul.
//
// Maintainer UX (Jacky):
//   - Already has the private repo at ~/Documents/Workspace/localkin/
//   - Studio tab auto-discovers content_director.soul.md + future
//     vertical-specific souls.
//   - Each soul card has Run (spawn `kinclaw -soul <path>`) + Reveal
//     in Finder + tail log.
//
// Why this is safe to ship in a public repo: this Swift file knows
// NOTHING about content_director, NotebookLM, R2, YouTube, or any
// vertical-specific business logic. It scans for files matching
// `*.soul.md` and lists their YAML frontmatter `name` + `description`.
// What those souls actually DO when invoked is none of this view's
// concern — that lives in the private sibling repo's skills + soul
// markdown body, which never enters this codebase.

struct StudioView: View {
    @StateObject private var loader = PrivateSoulLoader()

    var body: some View {
        NavigationStack {
            Group {
                if loader.souls.isEmpty {
                    EmptyStudioStateView(loader: loader)
                } else {
                    SoulListView(loader: loader)
                }
            }
            .navigationTitle("Studio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        loader.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Re-scan sibling private repo")
                }
            }
        }
        .onAppear { loader.rescan() }
    }
}

// MARK: - Empty state

/// Rendered when no sibling repo / no private souls are found. Public
/// users land here — the copy explains what Studio is for + how to
/// populate it. We deliberately avoid a marketing pitch tone: this is
/// a power-user feature, the empty state is documentation.
private struct EmptyStudioStateView: View {
    let loader: PrivateSoulLoader

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(Color("AccentGreen"))

            Text("No private souls detected")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Studio runs your *private* workflows alongside the public Agents tab — same window, separate codebase.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                Text("To populate this tab:")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                HStack(alignment: .top, spacing: 8) {
                    Text("1.")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create or clone a sibling repo at any of:")
                            .foregroundColor(.secondary)
                        ForEach(searchedPaths, id: \.self) { p in
                            Text(p)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("2.")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text("Drop `.soul.md` files into its `souls/private/` directory.")
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("3.")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text("Hit ↻ in the toolbar — your souls appear as cards.")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 480)

            if let last = loader.lastScan {
                Text("Last scan: \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Mirrors the candidate paths in PrivateSoulLoader.candidatePaths().
    /// We show the $HOME-substituted forms because raw NSHomeDirectory
    /// output is more honest about where the user should put things.
    private var searchedPaths: [String] {
        let h = NSHomeDirectory()
        return [
            "\(h)/Documents/Workspace/localkin/souls/private/",
            "\(h)/code/localkin/souls/private/",
            "\(h)/dev/localkin/souls/private/",
            "\(h)/src/localkin/souls/private/",
        ]
    }
}

// MARK: - Populated list

private struct SoulListView: View {
    @ObservedObject var loader: PrivateSoulLoader

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let repo = loader.siblingRepoPath {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.secondary)
                        Text(repo)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                ForEach(loader.souls) { soul in
                    PrivateSoulCard(soul: soul)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Individual soul card

private struct PrivateSoulCard: View {
    let soul: PrivateSoul

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(soul.displayName)
                        .font(.headline)
                    if let version = soul.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        revealInFinder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Button {
                        // Phase 1: log the intent. The actual spawn
                        // wiring lands in Phase 2 — we don't want a
                        // half-wired Run button that crashes when the
                        // user clicks it.
                        NSLog("[Studio] Run requested: \(soul.path)")
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentGreen"))
                    .help("Spawn kinclaw with this soul (Phase 2)")
                    .disabled(true)
                }
            }

            if let desc = soul.description {
                Text(desc)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let mtime = soul.modifiedAt {
                    Label {
                        Text("Updated \(mtime.formatted(.relative(presentation: .named)))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Text(soul.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: soul.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Preview

#Preview("Empty") {
    StudioView()
        .frame(width: 600, height: 500)
}
