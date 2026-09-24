import Foundation

// A port of `react-native-sdk/src/core/markdown.ts`: the same subset, the same answers.
// Output is plain data; there is no HTML anywhere, so nothing typed can become markup.

public indirect enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case lineBreak
    case code(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strike([MarkdownInline])
    case link(href: String, children: [MarkdownInline])
    /// A picture that came with the message, named by `Content-ID` rather than by URL.
    case image(cid: String, alt: String)
}

public enum MarkdownAlign: Equatable, Sendable {
    case left, center, right
}

public struct MarkdownCell: Equatable, Sendable {
    public var spans: [MarkdownInline]
    public var align: MarkdownAlign
}

public indirect enum MarkdownBlock: Equatable, Sendable {
    case paragraph([MarkdownInline])
    case heading(level: Int, spans: [MarkdownInline])
    case code(language: String, text: String)
    case quote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [[MarkdownBlock]])
    case table(head: [MarkdownCell], rows: [[MarkdownCell]])
    case rule
}

/// A small wrapper over `NSRegularExpression` with JS-like `test` and `exec`.
struct Pattern {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        // Patterns are literals in this file; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func test(_ string: String) -> Bool {
        let ns = string as NSString
        return regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// Group 0 and every capture; a group that did not take part is `nil`.
    func exec(_ string: String) -> [String?]? {
        let ns = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }
}

public enum Markdown {
    private static let fence = Pattern(#"^ {0,3}(```|~~~)[ \t]*([^\s`]*)"#)
    private static let heading = Pattern(#"^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$"#)
    private static let rule = Pattern(#"^ {0,3}([-*_])[ \t]*(?:\1[ \t]*){2,}$"#)
    private static let quote = Pattern(#"^ {0,3}>[ \t]?"#)
    private static let item = Pattern(#"^( *)([-*+]|[0-9]{1,9}[.)])[ \t]+(.*)$"#)
    private static let divider = Pattern(#"^ {0,3}\|?[ \t]*:?-{1,}:?[ \t]*(\|[ \t]*:?-{1,}:?[ \t]*)*\|?[ \t]*$"#)

    /// Schemes a link may carry. Anything else, `javascript:` above all, is not a link.
    private static let safe = Pattern(#"^(?:https?://|mailto:|tel:)[^\s]+$"#, caseInsensitive: true)
    private static let bareUrl = Pattern(#"^(?:https?://|www\.)[^\s<>\[\]()]*[^\s<>\[\]().,;:!?'"]"#, caseInsensitive: true)
    private static let email = Pattern(#"^[^\s@<>]+@[^\s@<>]+\.[a-z]{2,}$"#, caseInsensitive: true)
    private static let www = Pattern(#"^www\.[^\s]+$"#, caseInsensitive: true)
    private static let link = Pattern(#"^(!?)\[([^\]\[]*)\]\([ \t]*<?([^\s)]*)>?(?:[ \t]+"[^"]*")?[ \t]*\)"#)
    private static let cid = Pattern(#"^cid:(\S+)$"#, caseInsensitive: true)
    private static let codeSpan = Pattern(#"^(`+)([^`][\s\S]*?)\1(?!`)"#)
    private static let auto = Pattern(#"^<((?:https?://|mailto:)[^\s>]+)>"#, caseInsensitive: true)
    private static let escapable: Set<Character> = Set("\\`*_{}[]()#+-.!|~>")

    private enum Run { case strong, emphasis, strike }
    private static let runs: [(pattern: Pattern, kind: Run, wordish: Bool)] = [
        (Pattern(#"^\*\*(\S|\S[\s\S]*?\S)\*\*"#), .strong, false),
        (Pattern(#"^__(\S|\S[\s\S]*?\S)__"#), .strong, true),
        (Pattern(#"^~~(\S|\S[\s\S]*?\S)~~"#), .strike, false),
        (Pattern(#"^\*(\S|\S[\s\S]*?\S)\*"#), .emphasis, false),
        (Pattern(#"^_(\S|\S[\s\S]*?\S)_"#), .emphasis, true),
    ]

    /// Markdown source as blocks. Empty source is no blocks.
    public static func parse(_ source: String?) -> [MarkdownBlock] {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let normalised = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
        return blocks(normalised.components(separatedBy: "\n"))
    }

    /// A destination worth linking, or `nil`. Bare addresses and `www.` hosts are promoted.
    public static func safeHref(_ raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return nil }
        if safe.test(url) { return url }
        if email.test(url) { return "mailto:\(url)" }
        if www.test(url) { return "https://\(url)" }
        return nil
    }

    // MARK: - inline

    private static func isWord(_ unit: unichar?) -> Bool {
        guard let unit, unit < 128 else { return false }
        let c = Character(Unicode.Scalar(UInt8(unit)))
        return c.isLetter || c.isNumber || c == "_"
    }

    private static func string(_ units: [unichar]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }

    /// A bare URL keeps a trailing bracket only when the text opened one.
    private static func trimUrl(_ url: String) -> String {
        var chars = Array(url)
        while chars.last == ")" {
            let opens = chars.filter { $0 == "(" }.count
            let closes = chars.filter { $0 == ")" }.count
            if opens >= closes { break }
            chars.removeLast()
        }
        return String(chars)
    }

    /// The spans of one paragraph, heading or cell. `linkable` is false inside a link's own label.
    static func inline(_ source: String, linkable: Bool = true) -> [MarkdownInline] {
        let ns = source as NSString
        let length = ns.length
        var spans: [MarkdownInline] = []
        var plain: [unichar] = []
        var index = 0

        func flush() {
            if !plain.isEmpty { spans.append(.text(string(plain))) }
            plain = []
        }
        func unit(_ at: Int) -> unichar? { at >= 0 && at < length ? ns.character(at: at) : nil }
        func width(_ text: String) -> Int { (text as NSString).length }

        while index < length {
            let char = ns.character(at: index)
            let rest = ns.substring(from: index)
            let before = unit(index - 1)

            if char == 0x5C, let next = unit(index + 1), let scalar = Unicode.Scalar(next), escapable.contains(Character(scalar)) {
                plain.append(next)
                index += 2
                continue
            }

            if char == 0x0A {
                flush()
                spans.append(.lineBreak)
                index += 1
                continue
            }

            // Code first: everything inside it is literal.
            if char == 0x60, let code = codeSpan.exec(rest), let whole = code[0], let body = code[2] {
                flush()
                spans.append(.code(body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)))
                index += width(whole)
                continue
            }

            if char == 0x5B || char == 0x21, let match = link.exec(rest), let whole = match[0] {
                let bang = match[1] ?? ""
                if char == 0x5B || bang == "!" {
                    let label = match[2] ?? ""
                    let target = match[3] ?? ""
                    let cidMatch = bang == "!" ? cid.exec(target) : nil
                    let href = safeHref(target)
                    flush()
                    // A remote image becomes a link to it: in a support thread it is a tracking pixel.
                    if let cidMatch, let id = cidMatch[1] {
                        spans.append(.image(cid: id, alt: label))
                    } else if let href {
                        if bang == "!" {
                            spans.append(.link(href: href, children: [.text(label.isEmpty ? href : label)]))
                        } else {
                            spans.append(.link(href: href, children: inline(label, linkable: false)))
                        }
                    } else {
                        spans.append(contentsOf: inline(label, linkable: linkable))
                    }
                    index += width(whole)
                    continue
                }
            }

            if char == 0x3C, let match = auto.exec(rest), let whole = match[0], let target = match[1] {
                flush()
                if let href = safeHref(target) {
                    spans.append(.link(href: href, children: [.text(target)]))
                } else {
                    plain.append(contentsOf: Array(whole.utf16))
                }
                index += width(whole)
                continue
            }

            if char == 0x2A || char == 0x5F || char == 0x7E {
                var found: (Run, String, String)?
                for run in runs {
                    guard let match = run.pattern.exec(rest), let whole = match[0], let inner = match[1] else { continue }
                    // `snake_case_name` is one word: underscore runs only open and close at word boundaries.
                    if run.wordish && (isWord(before) || isWord(unit(index + width(whole)))) { continue }
                    found = (run.kind, whole, inner)
                    break
                }
                if let (kind, whole, inner) = found {
                    flush()
                    let children = inline(inner, linkable: linkable)
                    switch kind {
                    case .strong: spans.append(.strong(children))
                    case .emphasis: spans.append(.emphasis(children))
                    case .strike: spans.append(.strike(children))
                    }
                    index += width(whole)
                    continue
                }
            }

            let startsUrl = char == 0x68 || char == 0x77 || char == 0x48 || char == 0x57
            let glued = isWord(before) || before == 0x40 || before == 0x2F || before == 0x2E
            if linkable, startsUrl, !glued, let match = bareUrl.exec(rest), let whole = match[0] {
                let text = trimUrl(whole)
                if let href = safeHref(text) {
                    flush()
                    spans.append(.link(href: href, children: [.text(text)]))
                    index += width(text)
                    continue
                }
            }

            plain.append(char)
            index += 1
        }

        flush()
        return spans
    }

    // MARK: - blocks

    private static func indent(of line: String) -> Int {
        var count = 0
        for scalar in line.unicodeScalars {
            guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            count += scalar.utf16.count
        }
        return count
    }

    private static func slice(_ line: String, from offset: Int) -> String {
        let ns = line as NSString
        return offset >= ns.length ? "" : ns.substring(from: offset)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a line starts something of its own, and so cannot continue a paragraph.
    private static func opensBlock(_ line: String) -> Bool {
        fence.test(line) || heading.test(line) || rule.test(line) || quote.test(line) || item.test(line)
    }

    private static func cells(_ row: String) -> [String] {
        var trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        let chars = Array(trimmed)
        var out: [String] = []
        var current = ""
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\\" && index + 1 < chars.count && chars[index + 1] == "|" {
                current.append("|")
                index += 2
                continue
            }
            if char == "|" {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out
    }

    private static func alignments(_ divider: String) -> [MarkdownAlign] {
        cells(divider).map { cell in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left && right { return .center }
            return right ? .right : .left
        }
    }

    private static func isOrdered(_ marker: String) -> Bool {
        marker.contains { $0.isASCII && $0.isNumber }
    }

    /// One list, from its first marker to the first line that is no longer part of it.
    private static func list(_ lines: [String], from: Int) -> (block: MarkdownBlock, next: Int) {
        let first = item.exec(lines[from])!
        let marker = first[2] ?? ""
        let ordered = isOrdered(marker)
        let indentWidth = (first[1] ?? "").utf16.count
        var items: [[MarkdownBlock]] = []
        var index = from

        while index < lines.count {
            // A deeper marker belongs to the item above; a shallower one, or a switch of kind, is another list.
            guard let match = item.exec(lines[index]),
                  (match[1] ?? "").utf16.count == indentWidth,
                  ordered == isOrdered(match[2] ?? "")
            else { break }

            let content = (match[1] ?? "").utf16.count + (match[2] ?? "").utf16.count + 1
            var body = [match[3] ?? ""]
            index += 1

            while index < lines.count {
                let line = lines[index]
                if isBlank(line) {
                    let after = index + 1 < lines.count ? lines[index + 1] : nil
                    guard let after, !isBlank(after), indent(of: after) >= content || item.test(after) else { break }
                    body.append("")
                    index += 1
                    continue
                }
                if indent(of: line) >= content {
                    body.append(slice(line, from: content))
                    index += 1
                    continue
                }
                if opensBlock(line) { break }
                body.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                index += 1
            }

            items.append(blocks(body))
        }

        let start = ordered ? Int(marker.filter { $0.isASCII && $0.isNumber }) ?? 1 : 1
        return (.list(ordered: ordered, start: start, items: items), index)
    }

    private static func blocks(_ lines: [String]) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if isBlank(line) {
                index += 1
                continue
            }

            if let match = fence.exec(line) {
                let marker = NSRegularExpression.escapedPattern(for: match[1] ?? "```")
                let closes = Pattern("^ {0,3}\(marker)[ \\t]*$")
                var body: [String] = []
                index += 1
                while index < lines.count && !closes.test(lines[index]) {
                    body.append(lines[index])
                    index += 1
                }
                index += 1 // The closing fence, or the end when it was never written.
                out.append(.code(language: match[2] ?? "", text: body.joined(separator: "\n")))
                continue
            }

            if let match = heading.exec(line) {
                out.append(.heading(level: (match[1] ?? "#").count, spans: inline(match[2] ?? "")))
                index += 1
                continue
            }

            if rule.test(line) {
                out.append(.rule)
                index += 1
                continue
            }

            if quote.test(line) {
                var quoted: [String] = []
                while index < lines.count {
                    let next = lines[index]
                    if let match = quote.exec(next), let marker = match[0] {
                        quoted.append(slice(next, from: marker.utf16.count))
                    } else if !isBlank(next) && !opensBlock(next) {
                        quoted.append(next) // Wrapped, still quoted.
                    } else {
                        break
                    }
                    index += 1
                }
                out.append(.quote(blocks(quoted)))
                continue
            }

            if item.test(line) {
                let parsed = list(lines, from: index)
                out.append(parsed.block)
                index = parsed.next
                continue
            }

            if line.contains("|"), index + 1 < lines.count, divider.test(lines[index + 1]), lines[index + 1].contains("-") {
                let align = alignments(lines[index + 1])
                func row(_ text: String) -> [MarkdownCell] {
                    cells(text).enumerated().map { column, cell in
                        MarkdownCell(spans: inline(cell), align: column < align.count ? align[column] : .left)
                    }
                }
                let head = row(line)
                var rows: [[MarkdownCell]] = []
                index += 2
                while index < lines.count && !isBlank(lines[index]) && lines[index].contains("|") {
                    rows.append(row(lines[index]))
                    index += 1
                }
                out.append(.table(head: head, rows: rows))
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count && !isBlank(lines[index]) && !opensBlock(lines[index]) {
                paragraph.append(lines[index])
                index += 1
            }
            out.append(.paragraph(inline(paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))))
        }

        return out
    }
}
