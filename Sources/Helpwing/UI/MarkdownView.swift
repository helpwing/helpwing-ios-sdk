#if canImport(SwiftUI)
import SwiftUI

/// A message body rendered from markdown with SwiftUI's own text. Links open via `openURL`,
/// and only the schemes the parser allows (`http`, `https`, `mailto`, `tel`) ever become links.
public struct MarkdownView: View {
    private let blocks: [MarkdownBlock]
    private let style: MarkdownStyle

    /// - Parameters:
    ///   - color: The body colour; `muted` is for quotes, markers and rules.
    ///   - images: Picture URLs by `Content-ID`, from the message's own attachments.
    public init(
        _ source: String, theme: HelpwingTheme, color: String? = nil, muted: String? = nil,
        images: [String: String] = [:]
    ) {
        blocks = Markdown.parse(source)
        let body = color ?? theme.text
        style = MarkdownStyle(theme: theme, color: body, muted: muted ?? body, images: images)
    }

    public var body: some View {
        MarkdownBlocksView(blocks: blocks, style: style)
    }
}

struct MarkdownStyle {
    var theme: HelpwingTheme
    var color: String
    var muted: String
    var images: [String: String]

    /// The accent is the link colour except on the accent itself, where it would vanish.
    var linkColor: Color { Color(hex: color == theme.onAccent ? color : theme.accent) }

    func muting() -> MarkdownStyle {
        var copy = self
        copy.color = muted
        return copy
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let style: MarkdownStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, style: style)
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let style: MarkdownStyle

    private var theme: HelpwingTheme { style.theme }

    var body: some View {
        switch block {
        case .paragraph(let spans):
            MarkdownParagraph(spans: spans, style: style)

        case .heading(let level, let spans):
            styled(spans)
                .font(theme.font(level == 1 ? 19 : level == 2 ? 17 : level == 3 ? 16 : 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(theme.font(15))
                            .foregroundColor(Color(hex: style.muted))
                            .frame(width: 20, alignment: .leading)
                        MarkdownBlocksView(blocks: item, style: style)
                    }
                }
            }

        case .quote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Color(hex: style.muted)).frame(width: 2)
                MarkdownBlocksView(blocks: blocks, style: style.muting())
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: theme.text))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(Color(hex: theme.border))
            .cornerRadius(8)

        case .table(let head, let rows):
            VStack(spacing: 0) {
                row(head, bold: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    Rectangle().fill(Color(hex: style.muted)).frame(height: 0.5)
                    row(cells, bold: false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: style.muted), lineWidth: 1))

        case .rule:
            Rectangle().fill(Color(hex: style.muted)).frame(height: 1).opacity(0.5)
        }
    }

    private func styled(_ spans: [MarkdownInline]) -> some View {
        Text(MarkdownText.attributed(spans, style: style))
            .foregroundColor(Color(hex: style.color))
            .tint(style.linkColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ cells: [MarkdownCell], bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                if index > 0 { Rectangle().fill(Color(hex: style.muted)).frame(width: 1) }
                styled(cell.spans)
                    .font(theme.font(15, weight: bold ? .semibold : .regular))
                    .multilineTextAlignment(cell.align == .right ? .trailing : cell.align == .center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: cell.align == .right ? .trailing : cell.align == .center ? .center : .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A paragraph, with any picture that came with the message standing on its own line.
struct MarkdownParagraph: View {
    let spans: [MarkdownInline]
    let style: MarkdownStyle

    private enum Run {
        case words([MarkdownInline])
        case picture(url: String, alt: String)
    }

    private var runs: [Run] {
        var out: [Run] = []
        for span in spans {
            if case .image(let cid, let alt) = span, let url = style.images[cid] {
                out.append(.picture(url: url, alt: alt))
            } else if case .words(let current)? = out.last {
                out[out.count - 1] = .words(current + [span])
            } else {
                out.append(.words([span]))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .words(let words):
                    if MarkdownText.hasWords(words) {
                        Text(MarkdownText.attributed(words, style: style))
                            .font(style.theme.font(15))
                            .foregroundColor(Color(hex: style.color))
                            .tint(style.linkColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .picture(let url, let alt):
                    AsyncImage(url: URL(string: url)) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color(hex: style.theme.border).aspectRatio(1, contentMode: .fit)
                    }
                    .frame(maxHeight: 260)
                    .cornerRadius(8)
                    .accessibilityLabel(Text(alt))
                }
            }
        }
    }
}

enum MarkdownText {
    static func hasWords(_ spans: [MarkdownInline]) -> Bool {
        spans.contains {
            if case .text(let text) = $0 { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
    }

    /// Inline spans as one attributed string: intents for weight and style, `.link` for links.
    static func attributed(
        _ spans: [MarkdownInline], style: MarkdownStyle, intent: InlinePresentationIntent = []
    ) -> AttributedString {
        var out = AttributedString()
        for span in spans {
            switch span {
            case .text(let text):
                out += run(text, intent)
            case .lineBreak:
                out += run("\n", intent)
            case .code(let text):
                var code = run(text, intent.union(.code))
                code.font = .system(size: 13, design: .monospaced)
                out += code
            case .strong(let children):
                out += attributed(children, style: style, intent: intent.union(.stronglyEmphasized))
            case .emphasis(let children):
                out += attributed(children, style: style, intent: intent.union(.emphasized))
            case .strike(let children):
                var struck = attributed(children, style: style, intent: intent.union(.strikethrough))
                struck.foregroundColor = Color(hex: style.muted)
                out += struck
            case .link(let href, let children):
                var link = attributed(children, style: style, intent: intent)
                link.link = URL(string: href)
                link.underlineStyle = .single
                out += link
            case .image(_, let alt):
                // A picture whose file is not on the message: its alt text, as a mail client shows it.
                out += run(alt, intent)
            }
        }
        return out
    }

    private static func run(_ text: String, _ intent: InlinePresentationIntent) -> AttributedString {
        var string = AttributedString(text)
        if !intent.isEmpty { string.inlinePresentationIntent = intent }
        return string
    }
}
#endif
