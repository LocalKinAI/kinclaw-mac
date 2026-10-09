import SwiftUI

/// 秒出组件卡: an answer that comes with a small interface of its own (「都做吧」, 2026-10-08, after OpenAI's
/// Intelligent UI): the model writes a ```ui block — one element a line, `keyword words | columns` — and
/// it is drawn here, natively, as the words stream in. Numbers the person changes are worked out again
/// at once, here: a calc line is a formula over the inputs, evaluated by a small parser of our own (no
/// code runs). The pilot soul teaches the language (souls/pilot.soul.md, 「智能卡片」).
///
///     card 聚会预算
///     input 人数 people 8 min=1 max=50
///     slider 每人餐费 meal 120 min=30 max=500 step=10 unit=元
///     toggle 包饮料 drinks on
///     calc 每人分摊 = (people*meal + drinks*300)/people unit=元 digits=0
///     stat 年化 | 7% | 复利
///     compare 方案 | A | B        vs 价格 | ¥5999 | ¥4999
///     step 下载 | 从 App Store     time 1912 | 民国成立 | 清帝退位
///     bar 北京 | 2189 | 万人       row 名称 | 数量      check 盒子 | ok | 空闲
///     ask 换成五年期看看
struct UICardView: View {
    let spec: String

    @Environment(\.uiCardAsk) private var ask
    @Environment(\.uiCardSlot) private var slot
    /// What the person changed, by variable; the rest stay as the spec says.
    @State private var changed: [String: Double] = [:]

    var body: some View {
        let card = UICard.parse(spec)
        let values = card.values(with: changed)
        VStack(alignment: .leading, spacing: 10) {
            if let title = card.title {
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            ForEach(Array(card.groups.enumerated()), id: \.offset) { _, group in
                groupView(group, values)
            }
            if let slot { slot }
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.5))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func groupView(_ group: UICard.Group, _ values: [String: Double]) -> some View {
        switch group {
        case .text(let line):
            Text(LocalizedStringKey(line)).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .inputs(let inputs):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(inputs, id: \.name) { input in inputView(input, values) }
            }
        case .calcs(let calcs):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(calcs.enumerated()), id: \.offset) { index, calc in
                    HStack(alignment: .firstTextBaseline) {
                        Text(calc.label).font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(calc.show(values))
                            .font(.system(size: index == calcs.count - 1 ? 20 : 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(index == calcs.count - 1 ? Theme.accent : .primary)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: calc.show(values))
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.well))
        case .stats(let stats):
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat[0]).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Text(stat.count > 1 ? stat[1] : "").font(.system(size: 22, weight: .bold).monospacedDigit()).lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if stat.count > 2 { Text(stat[2]).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.well))
                }
            }
        case .table(let head, let rows, let compare):
            table(head, rows, compare)
        case .steps(let steps):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step[0]).font(.system(size: 13, weight: .semibold))
                            if step.count > 1 { Text(step[1]).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
        case .timeline(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item[0]).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                            .frame(width: 64, alignment: .trailing)
                        VStack(spacing: 0) {
                            Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(.top, 3)
                            if index < items.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 1.5).frame(maxHeight: .infinity) }
                        }
                        .frame(width: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.count > 1 ? item[1] : "").font(.system(size: 13, weight: .semibold))
                            if item.count > 2 { Text(item[2]).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
        case .bars(let bars):
            let top = max(bars.map(\.value).max() ?? 1, 0.000_001)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    HStack(spacing: 8) {
                        Text(bar.label).font(.system(size: 12)).frame(width: 72, alignment: .trailing).lineLimit(1)
                        GeometryReader { space in
                            RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.85))
                                .frame(width: max(2, space.size.width * bar.value / top))
                        }
                        .frame(height: 16)
                        Text(UICard.number(bar.value) + (bar.unit.isEmpty ? "" : " " + bar.unit))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 56, alignment: .leading)
                    }
                }
            }
        case .checks(let checks):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    HStack(spacing: 8) {
                        Circle().fill(check.count > 1 && check[1] == "ok" ? Theme.good : check.count > 1 && check[1] == "bad" ? Theme.bad : Theme.notice)
                            .frame(width: 8, height: 8)
                        Text(check[0]).font(.system(size: 13, weight: .medium))
                        if check.count > 2 { Text(check[2]).font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                }
            }
        case .asks(let asks):
            FlowLayout(spacing: 6) {
                ForEach(asks, id: \.self) { words in
                    Button { ask?(words) } label: { ChipLabel(title: words, symbol: "arrow.turn.down.right") }
                        .buttonStyle(.plain)
                        .disabled(ask == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func inputView(_ input: UICard.Input, _ values: [String: Double]) -> some View {
        let value = values[input.name] ?? input.value
        let binding = Binding(get: { value }, set: { changed[input.name] = $0 })
        switch input.kind {
        case .toggle:
            Toggle(input.label, isOn: Binding(get: { value != 0 }, set: { changed[input.name] = $0 ? 1 : 0 }))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
        case .slider:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(input.label).font(.system(size: 13))
                    Spacer()
                    Text(UICard.number(value) + (input.unit.isEmpty ? "" : " " + input.unit))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                Slider(value: binding, in: input.min...Swift.max(input.max, input.min + 0.000_001), step: input.step)
                    .controlSize(.small)
            }
        case .number:
            HStack {
                Text(input.label).font(.system(size: 13))
                Spacer(minLength: 12)
                TextField("", value: binding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                if !input.unit.isEmpty { Text(input.unit).font(.system(size: 12)).foregroundStyle(.secondary) }
                Stepper("", value: binding, in: input.min...Swift.max(input.max, input.min + 0.000_001), step: input.step).labelsHidden()
            }
        }
    }

    private func table(_ head: [String], _ rows: [[String]], _ compare: Bool) -> some View {
        let columns = max(head.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            if !head.isEmpty {
                GridRow {
                    ForEach(0..<columns, id: \.self) { index in
                        Text(index < head.count ? head[index] : "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(compare && index > 0 ? Theme.accent : .secondary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { index in
                        Text(index < row.count ? row[index] : "")
                            .font(.system(size: 13, weight: compare && index == 0 ? .medium : .regular))
                            .foregroundStyle(compare && index == 0 ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - The language

/// A ```ui block read into what is drawn: elements of a kind next to each other make one group (stats
/// in a row, steps in a list, a table).
struct UICard {
    struct Input {
        enum Kind { case number, slider, toggle }
        let kind: Kind
        let label: String
        let name: String
        let value: Double
        let min: Double
        let max: Double
        let step: Double
        let unit: String
    }

    struct Calc {
        let label: String
        let formula: String
        let unit: String
        let digits: Int?

        func show(_ values: [String: Double]) -> String {
            guard let value = UIFormula.evaluate(formula, values) else { return "…" }
            return UICard.number(value, digits: digits) + (unit.isEmpty ? "" : " " + unit)
        }
    }

    struct Bar {
        let label: String
        let value: Double
        let unit: String
    }

    enum Group {
        case text(String)
        case inputs([Input])
        case calcs([Calc])
        case stats([[String]])
        case table(head: [String], rows: [[String]], compare: Bool)
        case steps([[String]])
        case timeline([[String]])
        case bars([Bar])
        case checks([[String]])
        case asks([String])
    }

    var title: String?
    var groups: [Group] = []
    var inputs: [Input] = []
    var calcs: [Calc] = []

    /// The inputs' values (what the person changed, else what the spec says), then each calc in turn
    /// under its label — a later formula may use an earlier result by name (「月供 = 本金*月利率…」).
    func values(with changed: [String: Double]) -> [String: Double] {
        var values: [String: Double] = [:]
        for input in inputs { values[input.name] = changed[input.name] ?? input.value }
        for calc in calcs {
            if let value = UIFormula.evaluate(calc.formula, values) { values[calc.label] = value }
        }
        return values
    }

    static func parse(_ spec: String) -> UICard {
        var card = UICard()
        var table: (head: [String], rows: [[String]], compare: Bool)?
        func flush() {
            if let open = table { card.groups.append(.table(head: open.head, rows: open.rows, compare: open.compare)); table = nil }
        }
        func add(_ group: Group) {
            // The same kind as the last group: one group.
            switch (card.groups.last, group) {
            case (.inputs(let a)?, .inputs(let b)): card.groups[card.groups.count - 1] = .inputs(a + b)
            case (.calcs(let a)?, .calcs(let b)): card.groups[card.groups.count - 1] = .calcs(a + b)
            case (.stats(let a)?, .stats(let b)) where a.count < 4: card.groups[card.groups.count - 1] = .stats(a + b)
            case (.steps(let a)?, .steps(let b)): card.groups[card.groups.count - 1] = .steps(a + b)
            case (.timeline(let a)?, .timeline(let b)): card.groups[card.groups.count - 1] = .timeline(a + b)
            case (.bars(let a)?, .bars(let b)): card.groups[card.groups.count - 1] = .bars(a + b)
            case (.checks(let a)?, .checks(let b)): card.groups[card.groups.count - 1] = .checks(a + b)
            case (.asks(let a)?, .asks(let b)): card.groups[card.groups.count - 1] = .asks(a + b)
            default: card.groups.append(group)
            }
        }
        for raw in spec.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            let keyword = String(line.prefix { !$0.isWhitespace }).lowercased()
            let rest = line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
            let cells = rest.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if keyword != "row", keyword != "vs" { flush() }
            switch keyword {
            case "card", "title":
                if card.title == nil { card.title = rest } else { add(.text("**\(rest)**")) }
            case "text", "note":
                add(.text(rest))
            case "input", "number", "slider", "toggle":
                if let input = input(keyword, rest) {
                    card.inputs.removeAll { $0.name == input.name }
                    card.inputs.append(input)
                    add(.inputs([input]))
                }
            case "calc":
                if let calc = calc(rest) { card.calcs.append(calc); add(.calcs([calc])) }
            case "stat":
                add(.stats([cells]))
            case "compare":
                table = (cells, [], true)
            case "vs", "row":
                if table == nil { table = keyword == "row" ? (cells, [], false) : ([], [cells], true) } else { table?.rows.append(cells) }
            case "step":
                add(.steps([cells]))
            case "time":
                add(.timeline([cells]))
            case "bar":
                let number = cells.count > 1 ? Double(cells[1].replacingOccurrences(of: ",", with: "")) : nil
                if let number { add(.bars([Bar(label: cells[0], value: number, unit: cells.count > 2 ? cells[2] : "")])) }
            case "check", "status":
                add(.checks([cells]))
            case "ask", "chip":
                if !rest.isEmpty { add(.asks([rest])) }
            default:
                add(.text(line))
            }
        }
        flush()
        return card
    }

    /// `label name value key=value…` — the label may be several words; the name is the first word made of
    /// letters, digits and underscores that is followed by the value.
    private static func input(_ keyword: String, _ rest: String) -> Input? {
        var words = rest.split(separator: " ").map(String.init)
        var options: [String: String] = [:]
        words.removeAll { word in
            guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
            options[String(word[..<equals]).lowercased()] = String(word[word.index(after: equals)...])
            return true
        }
        guard words.count >= 2 else { return nil }
        let toggle = keyword == "toggle"
        let last = words.last!.lowercased()
        let value: Double
        if toggle { value = ["on", "true", "1", "开", "是"].contains(last) ? 1 : 0 } else {
            guard let number = Double(last.replacingOccurrences(of: ",", with: "")) else { return nil }
            value = number
        }
        let name = words[words.count - 2]
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
        let label = words.dropLast(2).joined(separator: " ")
        let low = options["min"].flatMap(Double.init) ?? (toggle ? 0 : min(0, value))
        let high = options["max"].flatMap(Double.init) ?? (toggle ? 1 : max(value * 2, value + 10))
        let step = options["step"].flatMap(Double.init) ?? (toggle ? 1 : (value == value.rounded() && high - low >= 10 ? 1 : (high - low) / 100))
        return Input(kind: toggle ? .toggle : keyword == "slider" ? .slider : .number, label: label.isEmpty ? name : label,
                     name: name, value: value, min: low, max: high, step: max(step, 0.000_001), unit: options["unit"] ?? "")
    }

    /// `label = formula key=value…`.
    private static func calc(_ rest: String) -> Calc? {
        guard let equals = rest.firstIndex(of: "=") else { return nil }
        let label = rest[..<equals].trimmingCharacters(in: .whitespaces)
        var formula = String(rest[rest.index(after: equals)...])
        var options: [String: String] = [:]
        while let match = formula.range(of: #"\s+(unit|digits|round)=(\S+)\s*$"#, options: .regularExpression) {
            let pair = formula[match].trimmingCharacters(in: .whitespaces)
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            options[parts[0]] = parts.count > 1 ? parts[1] : ""
            formula.removeSubrange(match)
        }
        return Calc(label: label, formula: formula.trimmingCharacters(in: .whitespaces), unit: options["unit"] ?? "",
                    digits: (options["digits"] ?? options["round"]).flatMap(Int.init))
    }

    static func number(_ value: Double, digits: Int? = nil) -> String {
        guard value.isFinite else { return "—" }
        // Under 1: three significant digits (a monthly rate of 0.00292 is not 0).
        let small = abs(value) < 1 && value != 0 ? min(8, 2 - Int(log10(abs(value)).rounded(.down))) : 2
        let places = digits ?? (abs(value) >= 1000 || value == value.rounded() ? 0 : abs(value) >= 10 ? 1 : small)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(0, places)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Arithmetic over named numbers: + - * / ^ %, parentheses, unary minus, and min max round abs sqrt pow
/// log log10 exp floor ceil. Nothing else is evaluated; anything it does not know is nil.
enum UIFormula {
    static func evaluate(_ text: String, _ values: [String: Double]) -> Double? {
        var reader = Reader(tokens: tokens(text), values: values)
        guard let value = reader.sum(), reader.at == reader.tokens.count, value.isFinite else { return nil }
        return value
    }

    enum Token: Equatable { case number(Double), name(String), symbol(Character) }

    private static func tokens(_ text: String) -> [Token] {
        var out: [Token] = []
        let chars = Array(text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_" { j += 1 }
                if let number = Double(String(chars[i..<j]).replacingOccurrences(of: "_", with: "")) { out.append(.number(number)) }
                i = j
            } else if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                out.append(.name(String(chars[i..<j])))
                i = j
            } else {
                out.append(.symbol(c))
                i += 1
            }
        }
        return out
    }

    private struct Reader {
        let tokens: [Token]
        let values: [String: Double]
        var at = 0

        mutating func take(_ symbol: Character) -> Bool {
            guard at < tokens.count, tokens[at] == .symbol(symbol) else { return false }
            at += 1
            return true
        }

        mutating func sum() -> Double? {
            guard var value = product() else { return nil }
            while true {
                if take("+") { guard let next = product() else { return nil }; value += next }
                else if take("-") { guard let next = product() else { return nil }; value -= next }
                else { return value }
            }
        }

        mutating func product() -> Double? {
            guard var value = power() else { return nil }
            while true {
                if take("*") { guard let next = power() else { return nil }; value *= next }
                else if take("/") { guard let next = power() else { return nil }; value /= next }
                else if take("%") { guard let next = power() else { return nil }; value = value.truncatingRemainder(dividingBy: next) }
                else { return value }
            }
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if take("^") { guard let exponent = power() else { return nil }; return pow(base, exponent) }
            return base
        }

        mutating func unary() -> Double? {
            if take("-") { return unary().map { -$0 } }
            if take("+") { return unary() }
            return atom()
        }

        mutating func atom() -> Double? {
            guard at < tokens.count else { return nil }
            switch tokens[at] {
            case .number(let n):
                at += 1
                return n
            case .symbol("("):
                at += 1
                guard let value = sum(), take(")") else { return nil }
                return value
            case .name(let name):
                at += 1
                if take("(") {
                    var arguments: [Double] = []
                    if !take(")") {
                        repeat {
                            guard let value = sum() else { return nil }
                            arguments.append(value)
                        } while take(",")
                        guard take(")") else { return nil }
                    }
                    return call(name.lowercased(), arguments)
                }
                switch name.lowercased() {
                case "pi": return Double.pi
                case "e": return M_E
                default: return values[name]
                }
            default:
                return nil
            }
        }

        func call(_ name: String, _ a: [Double]) -> Double? {
            switch (name, a.count) {
            case ("min", 1...): return a.min()
            case ("max", 1...): return a.max()
            case ("abs", 1): return abs(a[0])
            case ("sqrt", 1): return a[0].squareRoot()
            case ("pow", 2): return pow(a[0], a[1])
            case ("log", 1), ("ln", 1): return log(a[0])
            case ("log10", 1): return log10(a[0])
            case ("exp", 1): return exp(a[0])
            case ("floor", 1): return a[0].rounded(.down)
            case ("ceil", 1): return a[0].rounded(.up)
            case ("round", 1): return a[0].rounded()
            case ("round", 2): let k = pow(10, a[1]); return (a[0] * k).rounded() / k
            default: return nil
            }
        }
    }
}

// MARK: - What the card can do in its conversation

private struct UICardAskKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

private struct UICardSlotKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    /// An `ask` button's words, sent as the person's next message.
    var uiCardAsk: ((String) -> Void)? {
        get { self[UICardAskKey.self] }
        set { self[UICardAskKey.self] = newValue }
    }

    /// What goes at the bottom of the answer's card: its 「画给我看」.
    var uiCardSlot: AnyView? {
        get { self[UICardSlotKey.self] }
        set { self[UICardSlotKey.self] = newValue }
    }
}
