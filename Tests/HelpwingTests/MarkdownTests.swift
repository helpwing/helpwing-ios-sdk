import XCTest
@testable import Helpwing

/// The same questions `react-native-sdk/test/markdown.test.ts` asks.
final class MarkdownTests: XCTestCase {
    private func text(_ spans: [MarkdownInline]) -> String {
        spans.map { span -> String in
            switch span {
            case .text(let value), .code(let value): return value
            case .lineBreak: return "\n"
            case .strong(let children), .emphasis(let children), .strike(let children): return text(children)
            case .link(_, let children): return text(children)
            case .image(_, let alt): return alt
            }
        }.joined()
    }

    private func text(_ blocks: [MarkdownBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case .paragraph(let spans), .heading(_, let spans): return text(spans)
            case .quote(let inner): return text(inner)
            case .list(_, _, let items): return items.map { text($0) }.joined(separator: " ")
            case .code(_, let body): return body
            case .table, .rule: return ""
            }
        }.joined()
    }

    private func spans(_ source: String) -> [MarkdownInline] {
        guard case .paragraph(let spans)? = Markdown.parse(source).first else { return [] }
        return spans
    }

    func testEmptyDraftIsNothing() {
        XCTAssertEqual(Markdown.parse(""), [])
        XCTAssertEqual(Markdown.parse("   \n\n "), [])
        XCTAssertEqual(Markdown.parse(nil), [])
    }

    func testSingleNewlineIsABreak() {
        XCTAssertEqual(spans("Hi Rajiv,\nThanks for writing in."), [.text("Hi Rajiv,"), .lineBreak, .text("Thanks for writing in.")])
    }

    func testEmphasisKeepsTheWordsAround() {
        let result = spans("**no mail is being held.** What we *can* do is enable a domain.")
        guard case .strong = result.first else { return XCTFail("expected strong") }
        XCTAssertEqual(text(result), "no mail is being held. What we can do is enable a domain.")
        XCTAssertEqual(result.filter { if case .emphasis = $0 { return true } else { return false } }.count, 1)
    }

    func testUnderscoreInsideAWordIsLeftAlone() {
        XCTAssertEqual(spans("the field is body_text_html here"), [.text("the field is body_text_html here")])
    }

    func testListsAndTheirStart() {
        let bullets = Markdown.parse("- the From name is wrong\n- the footer is wrong")
        guard case .list(false, _, _)? = bullets.first else { return XCTFail("expected bullets") }
        XCTAssertEqual(text(bullets), "the From name is wrong the footer is wrong")

        guard case .list(true, 2, _)? = Markdown.parse("2. The agreement\n3. Written confirmation").first else {
            return XCTFail("expected a numbered list starting at 2")
        }
    }

    func testNestedList() {
        guard case .list(_, _, let items)? = Markdown.parse("- outer\n  - inner\n- second").first else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(items.count, 2)
        guard case .paragraph = items[0][0], case .list = items[0][1] else { return XCTFail("expected nesting") }
    }

    func testHeadingsQuotesRulesAndCode() {
        let blocks = Markdown.parse("## On the review\n\n> quoted line\n\n---\n\n```json\n{\"a\": 1}\n```")
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], .heading(level: 2, spans: [.text("On the review")]))
        XCTAssertEqual(blocks[1], .quote([.paragraph([.text("quoted line")])]))
        XCTAssertEqual(blocks[2], .rule)
        XCTAssertEqual(blocks[3], .code(language: "json", text: "{\"a\": 1}"))
    }

    func testMarkersInsideCodeAreLiteral() {
        let result = spans("the domain is `quickbooks-enterprises.com` **and** it is blocked")
        XCTAssertEqual(result[1], .code("quickbooks-enterprises.com"))
        XCTAssertTrue(result.contains { if case .strong = $0 { return true } else { return false } })
    }

    func testLinksAndBareAddresses() {
        let result = spans("I'd point you to the [brand use guide](https://quickbooks.intuit.com/help) instead.")
        XCTAssertEqual(result[1], .link(href: "https://quickbooks.intuit.com/help", children: [.text("brand use guide")]))
        XCTAssertEqual(text(result), "I'd point you to the brand use guide instead.")

        let bare = spans("One went to batkinson@occaps.com, a third party.")
        XCTAssertFalse(bare.contains { if case .link = $0 { return true } else { return false } })
    }

    func testAutolinkStopsBeforeTheSentence() {
        let result = spans("See https://helpwing.app/docs (the setup page).")
        XCTAssertTrue(result.contains(.link(href: "https://helpwing.app/docs", children: [.text("https://helpwing.app/docs")])))
    }

    func testTableWithAlignment() {
        guard case .table(let head, let rows)? = Markdown.parse("| Entity | Domain |\n| --- | ---: |\n| QB Enterprise | .com |").first else {
            return XCTFail("expected a table")
        }
        XCTAssertEqual(head.map { text($0.spans) }, ["Entity", "Domain"])
        XCTAssertEqual(head[1].align, .right)
        XCTAssertEqual(rows.count, 1)
    }

    func testCidImage() {
        XCTAssertEqual(spans("![the zone file](cid:shot-1@northwind)"), [.image(cid: "shot-1@northwind", alt: "the zone file")])
    }

    func testRemoteImageIsALink() {
        XCTAssertEqual(
            spans("![](https://tracker.example/open.gif)").first,
            .link(href: "https://tracker.example/open.gif", children: [.text("https://tracker.example/open.gif")])
        )
    }

    func testEscapedMarker() {
        let result = spans("a literal \\*asterisk\\* stays")
        XCTAssertEqual(text(result), "a literal *asterisk* stays")
        XCTAssertFalse(result.contains { if case .emphasis = $0 { return true } else { return false } })
    }

    func testEmojiSurvivesPlainText() {
        XCTAssertEqual(text(spans("Thanks 👍🏽 — **done**")), "Thanks 👍🏽 — done")
    }

    func testSafeHref() {
        XCTAssertEqual(Markdown.safeHref("https://helpwing.app"), "https://helpwing.app")
        XCTAssertEqual(Markdown.safeHref("mailto:support@helpwing.app"), "mailto:support@helpwing.app")
        XCTAssertEqual(Markdown.safeHref("support@helpwing.app"), "mailto:support@helpwing.app")
        XCTAssertEqual(Markdown.safeHref("www.helpwing.app"), "https://www.helpwing.app")
        XCTAssertNil(Markdown.safeHref("javascript:alert(1)"))
        XCTAssertNil(Markdown.safeHref("JavaScript:alert(1)"))
        XCTAssertNil(Markdown.safeHref("data:text/html;base64,PHNjcmlwdD4="))
        XCTAssertNil(Markdown.safeHref(""))
    }

    func testUnsafeLinkIsPrintedAsWords() {
        let result = spans("[click me](javascript:alert(1))")
        XCTAssertFalse(result.contains { if case .link = $0 { return true } else { return false } })
        XCTAssertTrue(text(result).contains("click me"))
    }
}
