import Foundation

/// Where the conversation is kept between launches. Anything with these three methods will do.
public protocol HelpwingStorage: AnyObject {
    func getItem(_ key: String) throws -> String?
    func setItem(_ key: String, _ value: String) throws
    func removeItem(_ key: String) throws
}

/// The default: survives relaunches, not reinstalls.
public final class UserDefaultsStorage: HelpwingStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func getItem(_ key: String) throws -> String? { defaults.string(forKey: key) }
    public func setItem(_ key: String, _ value: String) throws { defaults.set(value, forKey: key) }
    public func removeItem(_ key: String) throws { defaults.removeObject(forKey: key) }
}

/// Forgets everything when the process ends. For tests.
public final class MemoryStorage: HelpwingStorage {
    private var values: [String: String] = [:]

    public init() {}

    public func getItem(_ key: String) throws -> String? { values[key] }
    public func setItem(_ key: String, _ value: String) throws { values[key] = value }
    public func removeItem(_ key: String) throws { values[key] = nil }
}

public struct PendingMessage: Codable, Equatable, Sendable {
    public var clientMessageId: String
    public var text: String
    public var createdAt: String

    public init(clientMessageId: String, text: String, createdAt: String) {
        self.clientMessageId = clientMessageId
        self.text = text
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientMessageId = try c.decode(String.self, forKey: .clientMessageId)
        text = try c.decode(String.self, forKey: .text)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}

/// What survives the app being closed. Same JSON shape as the React Native SDK's record.
final class StoredSession: Codable {
    /// The only credential this client has, good for one conversation.
    var token: String
    var ticketId: String
    /// Who opened the conversation, as `identify()` named them. Empty when anonymous.
    var identityKey: String
    /// Where the update feed had got to.
    var cursor: String
    /// The server's cursor when the visitor last looked; everything after it is unread.
    var lastReadCursor: String
    /// Written but not yet acknowledged. Never the first message, which has no idempotency key.
    var pending: [PendingMessage]

    init(token: String, ticketId: String, identityKey: String, cursor: String, lastReadCursor: String, pending: [PendingMessage]) {
        self.token = token
        self.ticketId = ticketId
        self.identityKey = identityKey
        self.cursor = cursor
        self.lastReadCursor = lastReadCursor
        self.pending = pending
    }

    enum CodingKeys: String, CodingKey {
        case token, ticketId, identityKey, cursor, lastReadCursor, pending
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        ticketId = try c.decode(String.self, forKey: .ticketId)
        identityKey = (try? c.decodeIfPresent(String.self, forKey: .identityKey)) ?? ""
        cursor = (try? c.decodeIfPresent(String.self, forKey: .cursor)) ?? ""
        lastReadCursor = (try? c.decodeIfPresent(String.self, forKey: .lastReadCursor)) ?? ""
        let items = (try? c.decodeIfPresent([Lenient<PendingMessage>].self, forKey: .pending)) ?? []
        pending = items.compactMap(\.value)
    }
}

/// Decodes to nil instead of failing the whole array.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// One record per project key, so two projects keep two conversations.
struct SessionStore {
    private let storage: HelpwingStorage
    let key: String

    init(storage: HelpwingStorage, projectKey: String) {
        self.storage = storage
        key = "helpwing:\(projectKey)"
    }

    /// Anything unreadable is treated as nothing stored.
    func read() -> StoredSession? {
        guard let raw = try? storage.getItem(key), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func write(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session), let raw = String(data: data, encoding: .utf8) else { return }
        try? storage.setItem(key, raw)
    }

    func clear() {
        try? storage.removeItem(key)
    }
}
