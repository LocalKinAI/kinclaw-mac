import Foundation
import PDFKit

/// Two thousand books on a disk, sorted by a model that reads one page.
///
/// The shape is the one the games and the film's review arrived at: **the
/// program measures, the model judges.** Here the measuring is most of the
/// work and it is all free — a filename like `000-神农本草经-清-孙星衍.txt`
/// already holds the title, the dynasty and the author; the first page says
/// what kind of book it is far better than a title does. What is left over
/// is the one thing measuring cannot settle: which shelf it belongs on.
///
/// That question goes to Jev as one Choice question with the shelves as its
/// options, and what comes back is a probability for every shelf — not a
/// word. So a book that is 0.9 one thing is filed, and a book that is 0.3
/// against 0.28 is put aside to be looked at, which is the difference
/// between a catalogue and a pile. 150 ms and about 400 tokens a book: the
/// whole disk is a few minutes and a few cents.
@MainActor
final class BookShelf: ObservableObject {
    static let shared = BookShelf()

    struct Book: Codable, Identifiable, Equatable {
        var id: String { path }
        var path: String
        var title: String
        /// From the filename when it says so — `书名-朝代-作者`.
        var era: String?
        var author: String?
        var bytes: Int
        /// The shelf it was put on, and how sure the model was.
        var shelf: String?
        var sure: Double?
        /// The runner-up, which is what makes an uncertain answer readable.
        var second: String?
        /// What the book actually says: the opening, and two slices from
        /// further in. Kept so the list can be read and searched without
        /// opening two thousand files again.
        var opening: String?
        var middle: String?
        var later: String?
        var note: String?

        var name: String { (path as NSString).lastPathComponent }
        var unsure: Bool { (sure ?? 0) < 0.55 }
    }

    /// The shelves. Editable, because they are one library's shelves and not
    /// everybody's — and proposed from a sample rather than invented here.
    static let shelvesKey = "kinclaw.books.shelves"
    static let folderKey = "kinclaw.books.folder"
    static let defaultShelves = [
        "本草药物", "方剂", "伤寒金匮", "温病", "内科", "外科伤科", "妇科", "儿科",
        "针灸推拿", "医案医话", "诊法脉学", "养生食疗", "医经理论", "其他",
    ]
    static var shelves: [String] {
        let kept = UserDefaults.standard.stringArray(forKey: shelvesKey) ?? []
        return kept.isEmpty ? defaultShelves : kept
    }
    static var folder: String { UserDefaults.standard.string(forKey: folderKey) ?? "" }

    @Published private(set) var books: [Book] = []
    @Published private(set) var working: String?
    @Published private(set) var trouble: String?
    /// Input tokens spent on this shelf since the app started.
    @Published private(set) var tokens = 0
    private var work: Task<Void, Never>?

    private static var index: URL {
        let home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KinClawMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home.appendingPathComponent("books.json")
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.index),
              let kept = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = kept
    }

    private func save() {
        try? JSONEncoder().encode(books).write(to: Self.index, options: .atomic)
    }

    // MARK: Finding them

    static let readable: Set<String> = ["txt", "md", "pdf", "epub"]

    /// A disk with books on it also has source trees on it, and the first scan
    /// of this one filed twelve LICENSEs and four READMEs as books. Folders
    /// that belong to a checkout are skipped whole, and so are the dozen
    /// filenames every repository has.
    static let skipFolders: Set<String> = [
        ".git", ".svn", "node_modules", "site-packages", "venv", ".venv", "__pycache__",
        "build", "dist", "target", "vendor", "Pods", ".build", "DerivedData", ".cache", "Library",
    ]
    static let skipNames: Set<String> = [
        "license", "licence", "readme", "changelog", "contributing", "code_of_conduct", "code-of-conduct",
        "authors", "notice", "install", "manifest", "todo", "version", "security", "makefile",
        "requirements", "setup", "index", "api", "api_changes", "pffft", "booklist", "copying", "history",
    ]

    /// Is this a book, or a file that happens to be text?
    static func looksLikeABook(_ url: URL) -> Bool {
        guard readable.contains(url.pathExtension.lowercased()) else { return false }
        let parts = url.pathComponents
        if parts.contains(where: { skipFolders.contains($0) }) { return false }
        let stem = url.deletingPathExtension().lastPathComponent
        let bare = stem.lowercased().replacingOccurrences(of: " ", with: "_")
        if skipNames.contains(bare) { return false }
        // A repository's prose is ALL CAPS ASCII with no spaces; a book is not.
        if stem.count <= 24, stem.allSatisfy({ $0.isASCII && ($0.isUppercase || $0 == "_" || $0 == "-" || $0 == ".") }) { return false }
        return true
    }

    /// Walk a folder for books. Nothing is read here beyond the names: two
    /// thousand files is a second, and it is worth seeing the list before
    /// spending anything on it.
    func scan(_ root: String) -> Result<Int, FilmStudio.Failure> {
        guard !root.isEmpty else { return .failure(.message("先选一个文件夹")) }
        let base = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: base.path) else { return .failure(.message("找不到这个文件夹：\(base.path)")) }
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return .failure(.message("读不了这个文件夹"))
        }
        var found: [Book] = []
        let known = Dictionary(books.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        for case let url as URL in walk {
            guard Self.looksLikeABook(url),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 2_000 else { continue }                 // a page of nothing is not a book
            if var had = known[url.path] { had.bytes = size; found.append(had); continue }
            let named = Self.parse(url.deletingPathExtension().lastPathComponent)
            found.append(Book(path: url.path, title: named.title, era: named.era, author: named.author, bytes: size))
        }
        books = found.sorted { $0.title < $1.title }
        save()
        return .success(books.count)
    }

    /// `000-神农本草经-清-孙星衍` → title, era, author. A filename that is not
    /// of that shape is simply a title.
    static func parse(_ name: String) -> (title: String, era: String?, author: String?) {
        var parts = name.components(separatedBy: CharacterSet(charactersIn: "-－—_"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let first = parts.first, first.allSatisfy(\.isNumber) { parts.removeFirst() }
        guard parts.count >= 2 else { return (parts.first ?? name, nil, nil) }
        let dynasties = ["先秦", "秦", "汉", "东汉", "西汉", "三国", "魏", "晋", "南朝", "北朝", "隋", "唐", "五代",
                         "宋", "南宋", "北宋", "辽", "金", "元", "明", "清", "民国", "近代", "现代", "当代", "佚名"]
        if parts.count >= 3, dynasties.contains(parts[1]) {
            return (parts[0], parts[1], parts[2...].joined(separator: " "))
        }
        return (parts[0], nil, parts[1...].joined(separator: " "))
    }

    // MARK: Reading one

    /// What the book says, from three places.
    ///
    /// The first page alone was not enough and it showed: a Chinese medical
    /// text opens with somebody else's preface, or a table of contents, or a
    /// publisher's note, and none of those say what the book is. So the head
    /// is read and then two slices from a third and two thirds of the way in,
    /// where a book is actually itself. Seeking is free; only the tokens cost
    /// anything, and three slices is still under a fifth of a cent a book.
    ///
    /// Chinese books on a disk like this are a mix of UTF-8 and GB18030, and
    /// a slice from the middle starts in the middle of a character, so a few
    /// bytes are dropped from each end before decoding.
    static func read(_ path: String) -> (opening: String?, middle: String?, later: String?) {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "pdf" { return pdf(url) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil, nil) }
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0 ?? 0

        func slice(at offset: Int, bytes: Int, fromMiddle: Bool) -> String? {
            if offset > 0 { try? handle.seek(toOffset: UInt64(offset)) }
            guard let data = try? handle.read(upToCount: bytes), !data.isEmpty else { return nil }
            return tidy(decode(data, fromMiddle: fromMiddle))
        }
        let head = slice(at: 0, bytes: 5_000, fromMiddle: false)
        guard size > 20_000 else { return (head.map { String($0.prefix(1_200)) }, nil, nil) }
        let middle = slice(at: size / 3, bytes: 2_400, fromMiddle: true)
        let later = slice(at: size * 2 / 3, bytes: 2_400, fromMiddle: true)
        return (head.map { String($0.prefix(1_200)) },
                middle.map { String($0.prefix(500)) },
                later.map { String($0.prefix(500)) })
    }

    /// A PDF says what it is through PDFKit, which was reading nothing at all
    /// before: the thirty-six books in 属灵 were being filed on their titles.
    private static func pdf(_ url: URL) -> (String?, String?, String?) {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return (nil, nil, nil) }
        func page(_ index: Int) -> String? {
            guard index >= 0, index < document.pageCount else { return nil }
            return tidy(document.page(at: index)?.string)
        }
        let head = (0..<min(3, document.pageCount)).compactMap { page($0) }.joined(separator: " ")
        return (String(head.prefix(1_200)),
                page(document.pageCount / 3).map { String($0.prefix(500)) },
                page(document.pageCount * 2 / 3).map { String($0.prefix(500)) })
    }

    /// UTF-8, else GB18030 — the two this disk is made of.
    ///
    /// A slice of a file begins and ends in the middle of a character, and a
    /// decoder handed half a character returns nothing at all — not the rest
    /// of the text. That is not a corner case here: it silently emptied the
    /// first page of every book, including a 3.9 MB one that came back with
    /// no text whatsoever. So a few bytes are given up from each end until
    /// something decodes.
    private static func decode(_ data: Data, fromMiddle: Bool) -> String? {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for encoding in [String.Encoding.utf8, gb] {
            for lead in (fromMiddle ? [0, 1, 2, 3] : [0]) {
                for drop in [0, 1, 2, 3] {
                    guard data.count > lead + drop + 16 else { continue }
                    if let text = String(data: data.dropFirst(lead).dropLast(drop), encoding: encoding), !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    private static func tidy(_ text: String?) -> String? {
        guard let text else { return nil }
        let joined = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: Sorting them

    func stop() { work?.cancel(); work = nil; working = nil }

    /// Put every book that has no shelf on one. `again` re-files the ones
    /// already done, which is what to do after the shelves change.
    func sort(again: Bool = false, limit: Int? = nil) {
        guard work == nil else { trouble = "正在分类，先停下"; return }
        let shelves = Self.shelves
        guard shelves.count >= 2 else { trouble = "至少要两个类别"; return }
        let wanted = books.indices.filter { again || books[$0].shelf == nil }
        guard !wanted.isEmpty else { trouble = "没有要分的书了"; return }
        let todo = Array(limit.map { Array(wanted.prefix($0)) } ?? wanted)
        trouble = nil
        work = Task { @MainActor in
            defer { work = nil; working = nil }
            var done = 0
            for index in todo {
                if Task.isCancelled { break }
                working = "在分类 \(done + 1)/\(todo.count)：\(books[index].title)"
                let book = books[index]
                var pages = (opening: book.opening, middle: book.middle, later: book.later)
                if pages.opening == nil, pages.middle == nil { pages = Self.read(book.path) }
                books[index].opening = pages.opening
                books[index].middle = pages.middle
                books[index].later = pages.later
                do {
                    let put = try await Self.shelve(book, pages: pages, shelves: shelves)
                    books[index].shelf = put.shelf
                    books[index].sure = put.sure
                    books[index].second = put.second
                    books[index].note = nil
                    tokens += put.tokens
                } catch {
                    books[index].note = error.localizedDescription
                    // One book that cannot be filed is a note on that book; a
                    // key that is refused is every book, and stopping says so
                    // once instead of two thousand times.
                    if error.localizedDescription.contains("key") || error.localizedDescription.contains("401") {
                        trouble = error.localizedDescription
                        break
                    }
                }
                done += 1
                if done % 25 == 0 { save() }
            }
            save()
        }
    }

    /// One book, one Choice question, a probability for every shelf.
    static func shelve(_ book: Book, pages: (opening: String?, middle: String?, later: String?),
                       shelves: [String]) async throws -> (shelf: String, sure: Double, second: String?, tokens: Int) {
        var state: [(String, String)] = [("title", book.title)]
        if let era = book.era { state.append(("era", era)) }
        if let author = book.author { state.append(("author", author)) }
        if let opening = pages.opening, !opening.isEmpty { state.append(("first_page", opening)) }
        if let middle = pages.middle, !middle.isEmpty { state.append(("from_a_third_of_the_way_in", middle)) }
        if let later = pages.later, !later.isEmpty { state.append(("from_two_thirds_of_the_way_in", later)) }
        state.append(("file", book.name))
        let question = JevClient.Question(
            id: "shelf",
            question: "Which shelf does this book belong on?",
            howToJudge: "Judge by what the book is mostly about, not by a word in its title: a book of case records about fevers is case records, and a book named after a herb that is a formulary is a formulary. What the book SAYS decides — and the passages from a third and two thirds of the way in say it better than the first page, which is often somebody else's preface or a table of contents. If it fits none of the shelves, or fits several equally, choose the last one.",
            options: shelves.map { ($0, $0) })
        let reply = try await JevClient.ask(state: state, [question])
        guard let answer = reply.answers["shelf"] else { throw JevArcade.Failure.message("Jev 没回答这本书") }
        let ranked = answer.chances.sorted { $0.value > $1.value }
        let best = ranked.first?.key ?? answer.choice
        return (best, ranked.first?.value ?? answer.confidence ?? 0, ranked.dropFirst().first?.key, reply.tokens)
    }

    /// What is on each shelf, most first.
    var counted: [(shelf: String, books: [Book])] {
        let grouped = Dictionary(grouping: books.filter { $0.shelf != nil }) { $0.shelf! }
        return grouped.map { (shelf: $0.key, books: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.books.count > $1.books.count }
    }
}
