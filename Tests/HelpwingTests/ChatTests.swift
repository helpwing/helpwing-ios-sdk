import XCTest
@testable import Helpwing

@MainActor
final class ChatTests: XCTestCase {
    private let project = "pk_test"
    private var server: FakeServer!
    private var storage: MemoryStorage!

    override func setUp() async throws {
        server = FakeServer()
        storage = MemoryStorage()
    }

    /// Intervals long enough that no timer fires during a test; every poll is asked for.
    private func chat() -> HelpwingChat {
        HelpwingChat(
            apiUrl: "https://api.helpwing.test/", projectKey: project, storage: storage,
            pollInterval: 60, backgroundPollInterval: 60, http: server
        )
    }

    private func stored() -> [String: Any]? {
        guard let raw = try? storage.getItem("helpwing:\(project)") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
    }

    private var sends: [FakeServer.Call] { server.calls.filter { $0.path.hasSuffix("/messages/") } }
    private var start: FakeServer.Call? {
        server.calls.first { $0.method == "POST" && $0.path.hasSuffix("/conversations/") }
    }

    // MARK: starting up

    func testReadyOnceConfigLoads() async {
        let client = chat()
        await client.start()
        XCTAssertEqual(client.state.status, .ready)
        XCTAssertEqual(client.state.config?.projectName, "Acme Cloud")
        XCTAssertNil(client.state.conversation)
        XCTAssertEqual(server.calls.first?.path, "/widget/pk_test/config/")
    }

    func testDisabledWidgetIsUnconfigured() async {
        server.config.isEnabled = false
        let client = chat()
        await client.start()
        XCTAssertEqual(client.state.status, .unconfigured)
        XCTAssertNil(client.state.error)
    }

    func testHiddenOutsideHoursIsUnconfigured() async {
        server.config.isOnline = false
        server.config.hideWhenClosed = true
        let client = chat()
        await client.start()
        XCTAssertEqual(client.state.status, .unconfigured)
    }

    func testClosedButNotHiddenStaysReady() async {
        server.config.isOnline = false
        let client = chat()
        await client.start()
        XCTAssertEqual(client.state.status, .ready)
    }

    func testUnreachableReportsWithoutThrowing() async {
        server.failAll = .network
        let client = chat()
        await client.start()
        XCTAssertTrue(client.state.offline)
        XCTAssertEqual(client.state.status, .error)
    }

    // MARK: the first message

    func testFirstMessageOpensConversationAndStoresToken() async {
        let client = chat()
        await client.start()
        await client.send("The widget throws a CSP error.")

        XCTAssertEqual(client.state.conversation?.ticketId, "ticket-1")
        XCTAssertEqual(client.state.messages.map(\.text), ["The widget throws a CSP error."])
        XCTAssertEqual(client.state.messages.first?.delivery, .sent)
        XCTAssertEqual(stored()?["token"] as? String, "visitor-token-1")
        XCTAssertEqual(stored()?["ticketId"] as? String, "ticket-1")
    }

    func testStartCarriesNoIdempotencyKey() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        XCTAssertNotNil(start)
        XCTAssertNil(start?.body?["client_message_id"])
    }

    func testFailedStartIsShownNotRetried() async {
        let client = chat()
        await client.start()
        server.failNext = .network
        await client.send("Hello")

        XCTAssertEqual(client.state.messages.map(\.delivery), [.failed])
        XCTAssertNil(client.state.conversation)
        XCTAssertTrue(client.state.offline)
        XCTAssertNil(stored())
    }

    func testFailedStartGoesOutOnRetry() async throws {
        let client = chat()
        await client.start()
        server.failNext = .network
        await client.send("Hello")

        let failed = try XCTUnwrap(client.state.messages.first?.clientMessageId)
        await client.retry(failed)

        XCTAssertEqual(client.state.conversation?.ticketId, "ticket-1")
        XCTAssertEqual(client.state.messages.map(\.delivery), [.sent])
    }

    func testStartPassesEmailAndLocale() async {
        server.config.requireEmail = true
        let client = HelpwingChat(
            apiUrl: "https://api.helpwing.test", projectKey: project, storage: storage,
            pollInterval: 60, backgroundPollInterval: 60, locale: "ru", timezone: "Europe/Moscow", http: server
        )
        await client.start()
        await client.send("Hello", email: "kim@shop.example.com")

        XCTAssertEqual(start?.body?["email"] as? String, "kim@shop.example.com")
        XCTAssertEqual(start?.body?["locale"] as? String, "ru")
        XCTAssertEqual(start?.body?["timezone"] as? String, "Europe/Moscow")
    }

    // MARK: sending on a conversation that exists

    func testSendCarriesIdAndTwiceIsStoredOnce() async {
        let client = chat()
        await client.start()
        await client.send("First")

        server.failNext = .network
        await client.send("Second")
        XCTAssertEqual(client.state.messages.map(\.delivery), [.sent, .pending])

        await client.refresh()

        XCTAssertEqual(sends.count, 2)
        let ids = sends.map { $0.body?["client_message_id"] as? String }
        XCTAssertNotNil(ids[0])
        XCTAssertEqual(ids[0], ids[1])
        XCTAssertEqual(server.messages.filter { $0.bodyText == "Second" }.count, 1)
        XCTAssertEqual(client.state.messages.map(\.delivery), [.sent, .sent])
    }

    func testUnsentMessageSurvivesRelaunch() async {
        let first = chat()
        await first.start()
        await first.send("First")
        server.failNext = .network
        await first.send("Second")
        first.destroy()

        let second = chat()
        await second.start()

        XCTAssertEqual(server.messages.filter { $0.bodyText == "Second" }.count, 1)
        XCTAssertEqual(second.state.messages.map(\.text), ["First", "Second"])
    }

    func testQueueStopsAtFirstFailureSoOrderIsKept() async {
        let client = chat()
        await client.start()
        await client.send("First")

        server.failAll = .network
        await client.send("Second")
        await client.send("Third")
        server.failAll = nil
        await client.refresh()

        XCTAssertEqual(server.messages.map(\.bodyText), ["First", "Second", "Third"])
    }

    func testRefusedMessageIsFailedAndDropped() async {
        let client = chat()
        await client.start()
        await client.send("First")

        server.failNext = .status(400)
        await client.send("Second")

        XCTAssertEqual(client.state.messages.map(\.delivery), [.sent, .failed])
        XCTAssertEqual(client.state.error, "Refused by the fake server.")

        await client.refresh()
        XCTAssertEqual(sends.count, 1)
    }

    // MARK: following the conversation

    func testAgentReplyCountsUnreadUntilLookedAt() async {
        let client = chat()
        await client.start()
        await client.send("The widget throws a CSP error.")
        server.reply("Add the CSP header.")

        await client.refresh()

        XCTAssertEqual(client.state.messages.map(\.text), ["The widget throws a CSP error.", "Add the CSP header."])
        XCTAssertEqual(client.state.unreadCount, 1)

        client.setPresent(true)
        XCTAssertEqual(client.state.unreadCount, 0)
    }

    func testReplyIsMarkdownUnlessItArrivedAsHtml() async {
        let client = chat()
        await client.start()
        await client.send("The widget throws a CSP error.")
        server.reply("Add the **CSP** header.")
        server.messages.append(ApiMessage(
            id: "m-html", author: .agent, authorName: "Ada", bodyHtml: "<p>Sent from **my phone**</p>",
            createdAt: "2026-08-09T12:01:00.000Z"
        ))

        await client.refresh()

        XCTAssertEqual(client.state.messages.map(\.markdown), [true, true, false])
        XCTAssertEqual(client.state.messages.last?.text, "Sent from **my phone**")
    }

    func testCountsWhatArrivedWhileClosed() async {
        let first = chat()
        await first.start()
        await first.send("The widget throws a CSP error.")
        first.destroy()

        server.reply("Add the CSP header.")
        server.reply("Did that work?")

        let second = chat()
        await second.start()

        XCTAssertEqual(second.state.unreadCount, 2)
        XCTAssertEqual(second.state.messages.count, 3)
    }

    func testPresentOnlyWhileReading() async {
        let client = chat()
        await client.start()
        await client.send("Hello")

        await client.refresh()
        XCTAssertFalse(server.calls.last!.path.contains("present=1"))

        client.setPresent(true)
        await client.refresh()
        XCTAssertTrue(server.calls.last!.path.contains("present=1"))

        client.setPresent(false)
        await client.refresh()
        XCTAssertFalse(server.calls.last!.path.contains("present=1"))
    }

    func testNothingAskedInBackground() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        let before = server.calls.count

        client.setActive(false)
        await client.refresh()

        XCTAssertEqual(server.calls.count, before)
    }

    func testTypingShownAndCleared() async {
        let client = chat()
        await client.start()
        await client.send("Hello")

        server.typing = Typing(name: "Ada")
        await client.refresh()
        XCTAssertEqual(client.state.typing, Typing(name: "Ada"))

        server.typing = nil
        await client.refresh()
        XCTAssertNil(client.state.typing)
    }

    func testNeverShowsAMessageTwice() async {
        let client = chat()
        await client.start()
        await client.send("First")
        await client.send("Second")

        await client.refresh()
        await client.refresh()

        XCTAssertEqual(client.state.messages.map(\.text), ["First", "Second"])
    }

    func testPollsOnATimer() async throws {
        let client = HelpwingChat(
            apiUrl: "https://api.helpwing.test", projectKey: project, storage: storage,
            pollInterval: 0.05, backgroundPollInterval: 0.05, http: server
        )
        await client.start()
        await client.send("Hello")
        server.reply("Hi there")

        for _ in 0..<40 where client.state.messages.count < 2 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(client.state.messages.map(\.text), ["Hello", "Hi there"])
        client.destroy()
    }

    // MARK: a conversation the server no longer knows

    func testGoneConversationIsLetGo() async {
        let client = chat()
        await client.start()
        await client.send("Hello")

        server.conversationGone = true
        await client.refresh()
        server.conversationGone = false

        XCTAssertNil(client.state.conversation)
        XCTAssertEqual(client.state.messages, [])
        XCTAssertNil(stored())

        await client.send("Hello again")
        XCTAssertEqual(client.state.conversation?.ticketId, "ticket-1")
    }

    func testGoneConversationIsNotRestored() async {
        let first = chat()
        await first.start()
        await first.send("Hello")
        first.destroy()

        server.conversationGone = true
        let second = chat()
        await second.start()

        XCTAssertEqual(second.state.status, .ready)
        XCTAssertNil(second.state.conversation)
    }

    // MARK: who the visitor is

    func testIdentityKnownBeforehandGoesWithStart() async {
        let client = chat()
        await client.start()
        await client.identify(Identity(id: "user-42", email: "kim@shop.example.com", userHash: "abc"))
        await client.send("Hello")

        let identity = start?.body?["identity"] as? [String: String]
        XCTAssertEqual(identity, ["id": "user-42", "email": "kim@shop.example.com", "userHash": "abc"])
    }

    func testIdentityAttachedToStartedConversation() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        await client.identify(Identity(id: "user-42", userHash: "abc"))

        XCTAssertTrue(server.calls.contains { $0.path.hasSuffix("/identify/") })
    }

    func testIdentifyFailureIsNotAnError() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        server.failNext = .status(500)
        await client.identify(Identity(id: "user-42"))

        XCTAssertEqual(client.state.messages.count, 1)
    }

    func testSomebodyElseSigningInTakesConversationAway() async {
        let client = chat()
        await client.start()
        await client.identify(Identity(id: "user-a"))
        await client.send("Our invoices are wrong")
        XCTAssertEqual(client.state.messages.count, 1)

        await client.identify(Identity(id: "user-b"))

        XCTAssertFalse(server.calls.contains { $0.path.hasSuffix("/identify/") })
        XCTAssertNil(client.state.conversation)
        XCTAssertEqual(client.state.messages, [])
        XCTAssertNil(stored())
    }

    func testConflictFromServerLetsConversationGo() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        server.failNext = .status(409)
        await client.identify(Identity(id: "user-b"))

        XCTAssertNil(client.state.conversation)
        XCTAssertEqual(client.state.messages, [])
        XCTAssertNil(stored())
    }

    func testSameVisitorNamedAgainKeepsConversation() async {
        let client = chat()
        await client.start()
        await client.identify(Identity(id: "user-a"))
        await client.send("Hello")

        await client.identify(Identity(id: "user-a", name: "Ada"))

        XCTAssertEqual(client.state.messages.count, 1)
        XCTAssertTrue(server.calls.contains { $0.path.hasSuffix("/identify/") })
    }

    func testResetForgetsEverything() async {
        let client = chat()
        await client.start()
        await client.send("Hello")
        await client.reset()

        XCTAssertNil(client.state.conversation)
        XCTAssertEqual(client.state.messages, [])
        XCTAssertNil(stored())
    }

    // MARK: storage

    func testReadsARecordTheReactNativeSdkWrote() async {
        try? storage.setItem(
            "helpwing:\(project)",
            #"{"token":"visitor-token-1","ticketId":"ticket-1","cursor":"","lastReadCursor":"","pending":[{"clientMessageId":"c1","text":"Queued"}]}"#
        )
        let client = chat()
        await client.start()

        XCTAssertEqual(client.state.conversation?.ticketId, "ticket-1")
        XCTAssertEqual(server.messages.map(\.bodyText), ["Queued"])
    }

    func testUnreadableRecordIsNothingStored() async {
        try? storage.setItem("helpwing:\(project)", "{not json")
        let client = chat()
        await client.start()
        XCTAssertEqual(client.state.status, .ready)
        XCTAssertNil(client.state.conversation)
    }

    // MARK: subscribers

    func testSubscriberSeesNowAndEveryChange() async {
        var seen: [ChatState] = []
        let client = chat()
        let stop = client.subscribe { seen.append($0) }

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.status, .idle)

        await client.start()
        XCTAssertEqual(seen.last?.status, .ready)

        stop()
        let count = seen.count
        await client.send("Hello")
        XCTAssertEqual(seen.count, count)
    }

    func testHtmlIsFlattened() {
        XCTAssertEqual(HTMLText.plain("<p>One &amp; two</p><p>Three<br>four</p>"), "One & two\nThree\nfour")
    }
}
