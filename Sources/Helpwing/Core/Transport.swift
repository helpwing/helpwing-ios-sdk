import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP request, as plain data, so tests can answer it without a network.
public struct HelpwingRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
}

public struct HelpwingResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Whatever performs requests. Throwing means no answer arrived at all.
public protocol HelpwingHTTP {
    func perform(_ request: HelpwingRequest) async throws -> HelpwingResponse
}

public struct URLSessionHTTP: HelpwingHTTP {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func perform(_ request: HelpwingRequest) async throws -> HelpwingResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        return HelpwingResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}

/// A request that came back with an answer we did not want, or with none (`status` 0).
public struct HelpwingError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public let status: Int

    public init(_ message: String, status: Int) {
        self.message = message
        self.status = status
    }

    /// No answer at all: airplane mode, a dead tunnel, a captive portal.
    public var isNetwork: Bool { status == 0 }
    /// The visitor token names nothing any more.
    public var isGone: Bool { status == 404 }
    public var errorDescription: String? { message }
}

/// Every public widget endpoint, and nothing else.
struct Transport {
    /// `VISITOR_TOKEN_HEADER` on the server.
    static let visitorHeader = "X-Helpwing-Visitor"

    private let base: String
    private let http: HelpwingHTTP

    init(apiUrl: String, projectKey: String, http: HelpwingHTTP) {
        var root = apiUrl
        while root.hasSuffix("/") { root.removeLast() }
        base = "\(root)/widget/\(Transport.encode(projectKey))"
        self.http = http
    }

    func config() async throws -> WidgetConfig {
        try await request("GET", "/config/")
    }

    /// Takes no idempotency key: the server accepts none for a start, so a lost answer is a failed send.
    func start(bodyText: String, identity: Identity?, email: String, locale: String, timezone: String) async throws -> ApiConversation {
        struct Body: Encodable {
            let body_text: String
            let identity: Identity?
            let email: String?
            let locale: String?
            let timezone: String?
        }
        let body = Body(
            body_text: bodyText,
            identity: identity,
            email: email.isEmpty ? nil : email,
            locale: locale.isEmpty ? nil : locale,
            timezone: timezone.isEmpty ? nil : timezone
        )
        return try await request("POST", "/conversations/", body: body)
    }

    func conversation(ticketId: String, token: String) async throws -> ApiConversation {
        try await request("GET", "/conversations/\(ticketId)/", token: token)
    }

    /// Idempotent by `clientMessageId`: a retry stores nothing twice.
    func send(ticketId: String, token: String, bodyText: String, clientMessageId: String) async throws -> ApiConversation {
        struct Body: Encodable {
            let body_text: String
            let client_message_id: String
        }
        return try await request(
            "POST", "/conversations/\(ticketId)/messages/", token: token,
            body: Body(body_text: bodyText, client_message_id: clientMessageId)
        )
    }

    func identify(ticketId: String, token: String, identity: Identity) async throws {
        _ = try await raw("POST", "/conversations/\(ticketId)/identify/", token: token, body: identity)
    }

    /// `present` tells the server the visitor is reading, so a reply is not also emailed.
    func updates(ticketId: String, token: String, since: String, present: Bool) async throws -> ApiUpdates {
        var query = "since=\(Transport.encode(since))"
        if present { query += "&present=1" }
        return try await request("GET", "/conversations/\(ticketId)/updates/?\(query)", token: token)
    }

    // MARK: - plumbing

    private func request<T: Decodable>(
        _ method: String, _ path: String, token: String? = nil, body: Encodable? = nil
    ) async throws -> T {
        let response = try await raw(method, path, token: token, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw HelpwingError("The server's answer could not be read.", status: response.status)
        }
    }

    private func raw(
        _ method: String, _ path: String, token: String?, body: Encodable?
    ) async throws -> HelpwingResponse {
        guard let url = URL(string: base + path) else {
            throw HelpwingError("Invalid API URL: \(base + path)", status: 0)
        }
        var headers: [String: String] = ["Accept": "application/json"]
        var data: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            data = try JSONEncoder().encode(AnyEncodable(body))
        }
        if let token, !token.isEmpty { headers[Transport.visitorHeader] = token }

        let response: HelpwingResponse
        do {
            response = try await http.perform(HelpwingRequest(method: method, url: url, headers: headers, body: data))
        } catch {
            throw HelpwingError(error.localizedDescription, status: 0)
        }
        guard (200..<300).contains(response.status) else {
            throw HelpwingError(Transport.messageIn(response.body) ?? "HTTP \(response.status)", status: response.status)
        }
        return response
    }

    /// The API's error envelope, `{ "error": { "message": ... } }`.
    private static func messageIn(_ data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String, !message.isEmpty
        else { return nil }
        return message
    }

    static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
