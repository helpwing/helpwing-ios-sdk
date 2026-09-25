import XCTest
@testable import Helpwing

final class CopyTests: XCTestCase {
    private let base = WidgetConfig(
        projectName: "Acme Cloud", greeting: "Hi! How can we help?", offlineMessage: "We are offline right now.",
        typingText: "{name} is on it…"
    )
    private var translated: WidgetConfig {
        var config = base
        config.translations = [
            "ru": ["greeting": "Здравствуйте! Чем можем помочь?", "typing_text": "{name} печатает…"],
        ]
        return config
    }

    func testTranslationForTheLanguage() {
        XCTAssertEqual(Copy.forLocale(translated, .greeting, locale: "ru"), "Здравствуйте! Чем можем помочь?")
        XCTAssertEqual(Copy.forLocale(translated, .greeting, locale: "ru-RU"), "Здравствуйте! Чем можем помочь?")
        XCTAssertEqual(Copy.forLocale(translated, .typingText, locale: "ru"), "{name} печатает…")
    }

    func testFallsBackToTheProjectsOwnWords() {
        XCTAssertEqual(Copy.forLocale(translated, .greeting, locale: "de"), "Hi! How can we help?")
        XCTAssertEqual(Copy.forLocale(translated, .offlineMessage, locale: "ru"), "We are offline right now.")
        XCTAssertEqual(Copy.forLocale(translated, .greeting), "Hi! How can we help?")
        XCTAssertEqual(Copy.forLocale(base, .greeting, locale: "ru"), "Hi! How can we help?")
        XCTAssertEqual(Copy.forLocale(nil, .greeting, locale: "ru"), "")
        // No Russian typing_text of its own: falls back to the untranslated field, not blank.
        XCTAssertEqual(Copy.forLocale(base, .typingText, locale: "ru"), "{name} is on it…")
    }

    func testTypingTextBlankByDefault() {
        XCTAssertEqual(Copy.forLocale(WidgetConfig(), .typingText, locale: "ru"), "")
    }

    func testMatch() {
        let cases: [(String?, [String], String)] = [
            ("ru", ["ru", "en"], "ru"),
            ("ru-RU", ["ru"], "ru"),
            ("ru_RU", ["ru"], "ru"),
            ("RU", ["ru"], "ru"),
            ("pt-BR", ["pt"], "pt"),
            ("pt-BR", ["pt-br", "pt"], "pt-br"),
            ("de", ["ru", "en"], ""),
            ("", ["ru"], ""),
            (nil, ["ru"], ""),
        ]
        for (locale, available, expected) in cases {
            XCTAssertEqual(Copy.match(locale, available: available), expected, "\(locale ?? "nil") against \(available)")
        }
    }

    func testOlderServerConfigDecodes() throws {
        let json = ##"{"is_enabled":true,"project_name":"Acme","accent_color":"#fff","greeting":"Hi","is_online":true}"##
        let config = try JSONDecoder().decode(WidgetConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.colorScheme, .system)
        XCTAssertEqual(config.translations, [:])
        XCTAssertFalse(config.hideWhenClosed)
        XCTAssertEqual(config.title, "")
        XCTAssertEqual(config.typingText, "")
    }

    func testTypingTextDecodes() throws {
        let json = ##"{"is_enabled":true,"project_name":"Acme","accent_color":"#fff","typing_text":"{name} is typing a reply…","is_online":true}"##
        let config = try JSONDecoder().decode(WidgetConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.typingText, "{name} is typing a reply…")
    }
}

final class PaletteTests: XCTestCase {
    func testReadableOnAccent() {
        XCTAssertEqual(Palette.readableOn("#2563eb"), "#ffffff")
        XCTAssertEqual(Palette.readableOn("#c6ff3a"), "#101828")
        XCTAssertEqual(Palette.readableOn("#fff"), "#101828")
        XCTAssertEqual(Palette.readableOn("nonsense"), "#ffffff")
    }

    func testInvalidAccentFallsBack() {
        XCTAssertEqual(Palette.forAccent("blue").accent, Palette.defaultAccent)
        XCTAssertEqual(Palette.forAccent(nil, dark: true).background, "#0b0f19")
    }

    func testOverridesApplyOnTop() {
        let theme = Palette.forAccent("#2563eb").applying(.init(background: "#0a0a0b", fontFamily: "Fira Sans"))
        XCTAssertEqual(theme.background, "#0a0a0b")
        XCTAssertEqual(theme.accent, "#2563eb")
        XCTAssertEqual(theme.fontFamily, "Fira Sans")
    }
}
