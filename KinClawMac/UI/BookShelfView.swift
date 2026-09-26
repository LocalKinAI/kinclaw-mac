import SwiftUI
import AppKit

/// A disk of books, sorted. The left side is the shelves with their counts;
/// the right is what is on the one that is selected, with what the model was
/// not sure about at the top, because that is the only part a person has to
/// look at.
struct BookShelfView: View {
    @ObservedObject private var shelf = BookShelf.shared
    @AppStorage(BookShelf.folderKey) private var folder = ""
    @AppStorage(BookShelf.shelvesKey + ".text") private var shelvesText = BookShelf.defaultShelves.joined(separator: "、")
    @State private var picked: String?
    @State private var search = ""
    @State private var editing = false
    @State private var note: String?

    var body: some View {
        HStack(spacing: 0) {
            shelves.frame(width: 190)
            Divider().opacity(0.15)
            VStack(spacing: 0) {
                list
                Divider().opacity(0.15)
                bar
            }
        }
        .onAppear { if picked == nil { picked = shelf.counted.first?.shelf } }
    }

    // MARK: The shelves

    private var shelves: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                row("全部", count: shelf.books.count, tag: nil)
                let unsure = shelf.books.filter { $0.shelf != nil && $0.unsure }.count
                if unsure > 0 { row("要人看一眼", count: unsure, tag: "·unsure", colour: .orange) }
                let waiting = shelf.books.filter { $0.shelf == nil }.count
                if waiting > 0 { row("还没分", count: waiting, tag: "·todo", colour: .secondary) }
                Divider().opacity(0.12).padding(.vertical, 4)
                ForEach(shelf.counted, id: \.shelf) { entry in
                    row(entry.shelf, count: entry.books.count, tag: entry.shelf)
                }
            }
            .padding(8)
        }
    }

    private func row(_ title: String, count: Int, tag: String?, colour: Color = .primary) -> some View {
        Button { picked = tag } label: {
            HStack {
                Text(title).font(.system(size: 11, weight: picked == tag ? .semibold : .regular)).foregroundColor(colour)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(picked == tag ? Color.white.opacity(0.09) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: What is on it

    private var showing: [BookShelf.Book] {
        let wanted = search.trimmingCharacters(in: .whitespaces)
        return shelf.books.filter { book in
            switch picked {
            case nil: return true
            case "·unsure": return book.shelf != nil && book.unsure
            case "·todo": return book.shelf == nil
            default: return book.shelf == picked
            }
        }
        .filter { wanted.isEmpty || $0.title.localizedCaseInsensitiveContains(wanted)
                  || ($0.author ?? "").localizedCaseInsensitiveContains(wanted)
                  || ($0.opening ?? "").localizedCaseInsensitiveContains(wanted) }
        .sorted { ($0.unsure ? 0 : 1, $0.title) < ($1.unsure ? 0 : 1, $1.title) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(showing) { book in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            if let era = book.era { Text(era).font(.system(size: 9)).foregroundColor(.secondary) }
                            if let author = book.author { Text(author).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1) }
                            Spacer(minLength: 4)
                            if let put = book.shelf {
                                Text(put).font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill((book.unsure ? Color.orange : Theme.accent).opacity(0.22)))
                            }
                            if let sure = book.sure {
                                Text(String(format: "%.2f", sure)).font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(book.unsure ? .orange : .secondary)
                            }
                        }
                        if book.unsure, let second = book.second {
                            Text("也可能是「\(second)」").font(.system(size: 9)).foregroundColor(.orange)
                        }
                        if let opening = book.opening, !opening.isEmpty {
                            Text(opening).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
                        }
                        if let trouble = book.note {
                            Text(trouble).font(.system(size: 9)).foregroundColor(.red).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(fileURLWithPath: book.path)) }
                    .contextMenu {
                        Button("打开") { NSWorkspace.shared.open(URL(fileURLWithPath: book.path)) }
                        Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.path)]) }
                    }
                    Divider().opacity(0.07)
                }
                if showing.isEmpty {
                    Text(shelf.books.isEmpty ? "选一个文件夹，先「找书」" : "这一格是空的")
                        .font(.system(size: 11)).foregroundColor(.secondary).padding(20)
                }
            }
        }
    }

    // MARK: The bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("书在哪个文件夹？", text: $folder)
                    .textFieldStyle(.plain).font(.system(size: 11))
                Button("选…") { choose() }.controlSize(.small)
                Button("找书") { find() }.controlSize(.small)
                    .disabled(folder.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                TextField("搜书名、作者、第一页…", text: $search)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(maxWidth: 230)
                if let busy = shelf.working {
                    ProgressView().controlSize(.mini)
                    Text(busy).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                    Button("停") { shelf.stop() }.controlSize(.small)
                } else {
                    Button("分类") { shelf.sort() }.controlSize(.small)
                        .disabled(shelf.books.isEmpty)
                        .help("把还没分类的书交给 Jev：一本一道选择题，约 150 毫秒、几百 token")
                    Button("试 20 本") { shelf.sort(limit: 20) }.controlSize(.small).disabled(shelf.books.isEmpty)
                    Button("全部重分") { shelf.sort(again: true) }.controlSize(.small).disabled(shelf.books.isEmpty)
                }
                Spacer(minLength: 0)
                Button(editing ? "收起类别" : "改类别") { editing.toggle() }.controlSize(.small)
            }
            if editing {
                HStack(spacing: 8) {
                    TextField("类别，用、或逗号隔开", text: $shelvesText)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    Button("存") { saveShelves() }.controlSize(.small)
                }
                Text("改完要「全部重分」才会生效。最后一个类别是兜底，放不进前面任何一类的书会落在那里。")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            if let trouble = note ?? shelf.trouble {
                Text(trouble).font(.system(size: 10)).foregroundColor(.orange).lineLimit(2)
            }
            HStack(spacing: 10) {
                Text("\(shelf.books.count) 本 · 分好 \(shelf.books.filter { $0.shelf != nil }.count) · 要人看 \(shelf.books.filter { $0.shelf != nil && $0.unsure }.count)")
                if shelf.tokens > 0 {
                    Text("Jev 读了 \(shelf.tokens) token ≈ $\(String(format: "%.4f", Double(shelf.tokens) * 0.042 / 1_000_000))")
                }
            }
            .font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func find() {
        switch shelf.scan(folder) {
        case .success(let count): note = "找到 \(count) 本"; picked = nil
        case .failure(let failure): note = failure.localizedDescription
        }
    }

    private func saveShelves() {
        let parts = shelvesText.components(separatedBy: CharacterSet(charactersIn: "、,，\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2 else { note = "至少要两个类别"; return }
        UserDefaults.standard.set(parts, forKey: BookShelf.shelvesKey)
        note = "类别存好了（\(parts.count) 个）。「全部重分」生效"
        editing = false
    }
}
