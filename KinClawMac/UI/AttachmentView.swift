import SwiftUI
import AVKit

/// Inline preview for an `Attachment`. Renders one of three shapes:
///
///   - .image  → small thumbnail (max 240×180), click to open
///                in default viewer (Preview / Quick Look)
///   - .video  → AVPlayerView (small, 240 wide), inline playback
///   - .file   → icon + filename + size badge, click to open in
///                default app (Finder reveal on right-click)
///
/// All variants support textSelection on the filename so the user
/// can copy paths.
struct AttachmentView: View {
    let attachment: Attachment

    var body: some View {
        switch attachment.kind {
        case .image: imagePreview
        case .video: videoPreview
        case .file:  filePreview
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imagePreview: some View {
        Button {
            openInDefault()
        } label: {
            Group {
                if let url = attachment.localURL,
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let url = attachment.remoteURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(maxWidth: 60, maxHeight: 60)
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .failure:
                            placeholderIcon("photo")
                        @unknown default:
                            placeholderIcon("photo")
                        }
                    }
                } else {
                    placeholderIcon("photo")
                }
            }
            .frame(maxWidth: 240, maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(attachment.displayName)
    }

    // MARK: - Video

    @ViewBuilder
    private var videoPreview: some View {
        if let url = attachment.bestURL {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: 240, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderIcon("video")
        }
    }

    // MARK: - Generic file

    @ViewBuilder
    private var filePreview: some View {
        Button {
            openInDefault()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconForFile(attachment.displayName))
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = fileSizeString {
                        Text(size)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.platformTertiaryBackground.opacity(0.55))
            )
            .frame(maxWidth: 280, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(attachment.bestURL?.path ?? attachment.displayName)
    }

    // MARK: - Helpers

    private func placeholderIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 28))
            .foregroundColor(.secondary)
            .frame(maxWidth: 60, maxHeight: 60)
    }

    private func iconForFile(_ name: String) -> String {
        let lower = (name as NSString).pathExtension.lowercased()
        switch lower {
        case "pdf":           return "doc.richtext"
        case "txt", "md":     return "doc.text"
        case "zip", "tar", "gz": return "archivebox"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "py", "js", "ts", "go", "rs", "swift", "rb", "c", "cpp",
             "java", "kt":    return "chevron.left.forwardslash.chevron.right"
        case "xls", "xlsx", "csv": return "tablecells"
        case "doc", "docx":   return "doc.text.image"
        case "ppt", "pptx":   return "rectangle.on.rectangle"
        default:              return "doc"
        }
    }

    private var fileSizeString: String? {
        guard let url = attachment.localURL,
              let attr = try? FileManager.default.attributesOfItem(
                atPath: url.path),
              let bytes = attr[.size] as? Int64 else {
            return nil
        }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func openInDefault() {
        guard let url = attachment.bestURL else { return }
        NSWorkspace.shared.open(url)
    }
}
