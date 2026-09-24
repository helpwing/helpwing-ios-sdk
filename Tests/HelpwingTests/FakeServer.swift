import Foundation
@testable import Helpwing

/// A stand-in for the public widget API.
@MainActor
final class FakeServer: HelpwingHTTP {
    struct Call {
        let method: String
        let path: String
        let token: String?
        let body: [String: Any]?
    }

    enum Failure {
        case network
        case status(Int)
    }

    struct NetworkDown: Error {}

    var calls: [Call] = []
    var config = WidgetConfig(
        isEnabled: true,
        projectName: "Acme Cloud",
        accentColor: "#2563eb",
        greeting: "Hi! How can we help?",
        offlineMessage: "We are offline right now.",
        requireEmail: false,
        showAgentAvailability: true,
        isOnline: true
    )
    var messages: [ApiMessage] = []
    var token = "visitor-token-1"
    var ticketId = "ticket-1"
    var typing: Typing?

    /// Fails the next request only.
    var failNext: Failure?
    /// Fails every request until cleared.
    var failAll: Failure?
    /// Everything about the conversation answers 404.
    var conversationGone = false

    private var clock = 0

    func perform(_ request: HelpwingRequest) async throws -> HelpwingResponse {
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
        let path = components.percentEncodedPath + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        calls.append(Call(method: request.method, path: path, token: request.headers["X-Helpwing-Visitor"], body: body))

        let failure = failNext ?? failAll
        failNext = nil
        switch failure {
        case .network: throw NetworkDown()
        case .status(let status): return answer(status, ["error": ["message": "Refused by the fake server."]])
        case nil: break
        }
        return route(components, method: request.method, body: body)
    }

    @discardableResult
    func reply(_ text: String, name: String = "Ada") -> ApiMessage {
        let message = self.message(author: .agent, authorName: name, bodyText: text)
        messages.append(message)
        return message
    }

    func message(author: Author, authorName: String = "", bodyText: String = "", clientMessageId: String = "") -> ApiMessage {
        ApiMessage(
            id: "m\(messages.count + 1)", author: author, authorName: authorName, bodyText: bodyText,
            createdAt: now(), clientMessageId: clientMessageId
        )
    }

    private func route(_ url: URLComponents, method: String, body: [String: Any]?) -> HelpwingResponse {
        let path = url.path

        if path.hasSuffix("/config/") { return answer(200, config) }

        if conversationGone && path.contains("/conversations/") && !path.hasSuffix("/conversations/") {
            return answer(404, ["error": ["message": "No conversation was found for that visitor token."]])
        }

        if path.hasSuffix("/conversations/") && method == "POST" {
            messages.append(message(author: .customer, bodyText: body?["body_text"] as? String ?? ""))
            return answer(201, conversation(token: token, only: Array(messages.suffix(1))))
        }

        if path.hasSuffix("/messages/") && method == "POST" {
            let clientId = body?["client_message_id"] as? String ?? ""
            let already = messages.first { !clientId.isEmpty && $0.clientMessageId == clientId }
            let stored = already ?? message(author: .customer, bodyText: body?["body_text"] as? String ?? "", clientMessageId: clientId)
            if already == nil { messages.append(stored) }
            return answer(201, conversation(only: [stored]))
        }

        if path.hasSuffix("/identify/") {
            return answer(200, ["customer_id": "c1", "is_identity_verified": false])
        }

        if path.hasSuffix("/updates/") {
            let since = url.queryItems?.first { $0.name == "since" }?.value ?? ""
            let fresh = messages.filter { $0.createdAt > since }
            return answer(200, ApiUpdates(cursor: now(), hasChanges: !fresh.isEmpty, status: "open", messages: fresh, typing: typing))
        }

        if method == "GET" { return answer(200, conversation()) }
        return answer(404, ["error": ["message": "No such thing."]])
    }

    private func conversation(token: String = "", only: [ApiMessage]? = nil) -> ApiConversation {
        ApiConversation(
            ticketId: ticketId, ticketReference: "k7m2p9qx3r", status: "open",
            subject: "The widget throws a CSP error", visitorToken: token,
            messages: only ?? messages, typing: typing, cursor: now()
        )
    }

    /// A clock that only goes forwards, so cursors order the way real timestamps do.
    func now() -> String {
        clock += 1
        return String(format: "2026-08-09T12:%02d:%02d.000Z", clock / 60, clock % 60)
    }

    private func answer<T: Encodable>(_ status: Int, _ payload: T) -> HelpwingResponse {
        HelpwingResponse(status: status, body: try! JSONEncoder().encode(payload))
    }

    private func answer(_ status: Int, _ payload: [String: Any]) -> HelpwingResponse {
        HelpwingResponse(status: status, body: try! JSONSerialization.data(withJSONObject: payload))
    }
}
