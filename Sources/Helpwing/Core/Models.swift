import Foundation

// Wire shapes of the public widget API. Every field decodes
// with a fallback, so a build talking to an older or newer server still reads it.

extension KeyedDecodingContainer {
    fileprivate func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

/// `GET /widget/{public_key}/config/`
public struct WidgetConfig: Codable, Equatable, Sendable {
    public enum ColorScheme: String, Codable, Sendable {
        case system, light, dark
    }

    public var isEnabled: Bool
    public var projectName: String
    public var accentColor: String
    /// Resolved on the device; an older server sends nothing, which reads as `system`.
    public var colorScheme: ColorScheme
    public var launcherIcon: String
    public var launcherIconUrl: String
    public var launcherPosition: String
    public var logoUrl: String
    public var showBranding: Bool
    /// Blank when the project wrote no heading of its own.
    public var title: String
    public var greeting: String
    public var offlineMessage: String
    /// Shown while an agent is typing, with `{name}` for their name. Blank keeps the built-in label.
    public var typingText: String
    /// Title, greeting, offline message and typing text per language code. Read through `Copy.forLocale`.
    public var translations: [String: [String: String]]
    public var defaultLocale: String
    public var requireEmail: Bool
    public var showAgentAvailability: Bool
    public var showOnDesktop: Bool
    public var showOnMobile: Bool
    public var identityVerificationEnabled: Bool
    public var isOnline: Bool
    /// The project hides the chat outside its hours rather than showing the offline message.
    public var hideWhenClosed: Bool

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case projectName = "project_name"
        case accentColor = "accent_color"
        case colorScheme = "color_scheme"
        case launcherIcon = "launcher_icon"
        case launcherIconUrl = "launcher_icon_url"
        case launcherPosition = "launcher_position"
        case logoUrl = "logo_url"
        case showBranding = "show_branding"
        case title, greeting
        case offlineMessage = "offline_message"
        case typingText = "typing_text"
        case translations
        case defaultLocale = "default_locale"
        case requireEmail = "require_email"
        case showAgentAvailability = "show_agent_availability"
        case showOnDesktop = "show_on_desktop"
        case showOnMobile = "show_on_mobile"
        case identityVerificationEnabled = "identity_verification_enabled"
        case isOnline = "is_online"
        case hideWhenClosed = "hide_when_closed"
    }

    public init(
        isEnabled: Bool = true,
        projectName: String = "",
        accentColor: String = Palette.defaultAccent,
        colorScheme: ColorScheme = .system,
        launcherIcon: String = "chat",
        launcherIconUrl: String = "",
        launcherPosition: String = "bottom_right",
        logoUrl: String = "",
        showBranding: Bool = true,
        title: String = "",
        greeting: String = "",
        offlineMessage: String = "",
        typingText: String = "",
        translations: [String: [String: String]] = [:],
        defaultLocale: String = "",
        requireEmail: Bool = false,
        showAgentAvailability: Bool = false,
        showOnDesktop: Bool = true,
        showOnMobile: Bool = true,
        identityVerificationEnabled: Bool = false,
        isOnline: Bool = true,
        hideWhenClosed: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.projectName = projectName
        self.accentColor = accentColor
        self.colorScheme = colorScheme
        self.launcherIcon = launcherIcon
        self.launcherIconUrl = launcherIconUrl
        self.launcherPosition = launcherPosition
        self.logoUrl = logoUrl
        self.showBranding = showBranding
        self.title = title
        self.greeting = greeting
        self.offlineMessage = offlineMessage
        self.typingText = typingText
        self.translations = translations
        self.defaultLocale = defaultLocale
        self.requireEmail = requireEmail
        self.showAgentAvailability = showAgentAvailability
        self.showOnDesktop = showOnDesktop
        self.showOnMobile = showOnMobile
        self.identityVerificationEnabled = identityVerificationEnabled
        self.isOnline = isOnline
        self.hideWhenClosed = hideWhenClosed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = c.value(.isEnabled, false)
        projectName = c.value(.projectName, "")
        accentColor = c.value(.accentColor, "")
        colorScheme = c.value(.colorScheme, .system)
        launcherIcon = c.value(.launcherIcon, "")
        launcherIconUrl = c.value(.launcherIconUrl, "")
        launcherPosition = c.value(.launcherPosition, "")
        logoUrl = c.value(.logoUrl, "")
        showBranding = c.value(.showBranding, true)
        title = c.value(.title, "")
        greeting = c.value(.greeting, "")
        offlineMessage = c.value(.offlineMessage, "")
        typingText = c.value(.typingText, "")
        translations = c.value(.translations, [:])
        defaultLocale = c.value(.defaultLocale, "")
        requireEmail = c.value(.requireEmail, false)
        showAgentAvailability = c.value(.showAgentAvailability, false)
        showOnDesktop = c.value(.showOnDesktop, true)
        showOnMobile = c.value(.showOnMobile, true)
        identityVerificationEnabled = c.value(.identityVerificationEnabled, false)
        isOnline = c.value(.isOnline, true)
        hideWhenClosed = c.value(.hideWhenClosed, false)
    }
}

public struct ApiAttachment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var filename: String
    public var contentType: String
    public var sizeBytes: Int
    /// Signed and short-lived: minted fresh on every read.
    public var url: String
    /// A picture written into the body as `![alt](cid:<contentId>)` rather than a file alongside.
    public var isInline: Bool
    public var contentId: String

    enum CodingKeys: String, CodingKey {
        case id, filename, url
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
        case isInline = "is_inline"
        case contentId = "content_id"
    }

    public init(
        id: String, filename: String, contentType: String = "", sizeBytes: Int = 0,
        url: String = "", isInline: Bool = false, contentId: String = ""
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.url = url
        self.isInline = isInline
        self.contentId = contentId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        filename = c.value(.filename, "")
        contentType = c.value(.contentType, "")
        sizeBytes = c.value(.sizeBytes, 0)
        url = c.value(.url, "")
        isInline = c.value(.isInline, false)
        contentId = c.value(.contentId, "")
    }
}

public enum Author: String, Codable, Sendable {
    case agent, customer, system

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Author(rawValue: raw) ?? .system
    }
}

public struct ApiMessage: Codable, Equatable, Sendable {
    public var id: String
    public var author: Author
    public var authorName: String
    public var authorAvatarUrl: String
    public var bodyText: String
    public var bodyHtml: String
    public var attachments: [ApiAttachment]
    public var createdAt: String
    /// The id this client gave the message, when it sent it. Empty on anything else.
    public var clientMessageId: String

    enum CodingKeys: String, CodingKey {
        case id, author, attachments
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case bodyText = "body_text"
        case bodyHtml = "body_html"
        case createdAt = "created_at"
        case clientMessageId = "client_message_id"
    }

    public init(
        id: String, author: Author, authorName: String = "", authorAvatarUrl: String = "",
        bodyText: String = "", bodyHtml: String = "", attachments: [ApiAttachment] = [],
        createdAt: String, clientMessageId: String = ""
    ) {
        self.id = id
        self.author = author
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.createdAt = createdAt
        self.clientMessageId = clientMessageId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        author = c.value(.author, .system)
        authorName = c.value(.authorName, "")
        authorAvatarUrl = c.value(.authorAvatarUrl, "")
        bodyText = c.value(.bodyText, "")
        bodyHtml = c.value(.bodyHtml, "")
        attachments = c.value(.attachments, [])
        createdAt = c.value(.createdAt, "")
        clientMessageId = c.value(.clientMessageId, "")
    }
}

public struct Typing: Codable, Equatable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
    }
}

public struct ApiConversation: Codable, Equatable, Sendable {
    public var ticketId: String
    public var ticketReference: String
    public var status: String
    public var subject: String
    public var visitorToken: String
    public var messages: [ApiMessage]
    public var typing: Typing?
    public var cursor: String

    enum CodingKeys: String, CodingKey {
        case status, subject, messages, typing, cursor
        case ticketId = "ticket_id"
        case ticketReference = "ticket_reference"
        case visitorToken = "visitor_token"
    }

    public init(
        ticketId: String, ticketReference: String = "", status: String = "open", subject: String = "",
        visitorToken: String = "", messages: [ApiMessage] = [], typing: Typing? = nil, cursor: String = ""
    ) {
        self.ticketId = ticketId
        self.ticketReference = ticketReference
        self.status = status
        self.subject = subject
        self.visitorToken = visitorToken
        self.messages = messages
        self.typing = typing
        self.cursor = cursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticketId = c.value(.ticketId, "")
        ticketReference = c.value(.ticketReference, "")
        status = c.value(.status, "")
        subject = c.value(.subject, "")
        visitorToken = c.value(.visitorToken, "")
        messages = c.value(.messages, [])
        typing = c.value(.typing, nil)
        cursor = c.value(.cursor, "")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ticketId, forKey: .ticketId)
        try c.encode(ticketReference, forKey: .ticketReference)
        try c.encode(status, forKey: .status)
        try c.encode(subject, forKey: .subject)
        try c.encode(visitorToken, forKey: .visitorToken)
        try c.encode(messages, forKey: .messages)
        try c.encode(typing, forKey: .typing)
        try c.encode(cursor, forKey: .cursor)
    }
}

public struct ApiUpdates: Codable, Equatable, Sendable {
    public var cursor: String
    public var hasChanges: Bool
    public var status: String
    public var messages: [ApiMessage]
    public var typing: Typing?

    enum CodingKeys: String, CodingKey {
        case cursor, status, messages, typing
        case hasChanges = "has_changes"
    }

    public init(cursor: String, hasChanges: Bool, status: String, messages: [ApiMessage], typing: Typing?) {
        self.cursor = cursor
        self.hasChanges = hasChanges
        self.status = status
        self.messages = messages
        self.typing = typing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cursor = c.value(.cursor, "")
        hasChanges = c.value(.hasChanges, false)
        status = c.value(.status, "")
        messages = c.value(.messages, [])
        typing = c.value(.typing, nil)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cursor, forKey: .cursor)
        try c.encode(hasChanges, forKey: .hasChanges)
        try c.encode(status, forKey: .status)
        try c.encode(messages, forKey: .messages)
        try c.encode(typing, forKey: .typing)
    }
}

/// A value in `Identity.metadata`.
public enum MetadataValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        }
    }
}

/// Who the visitor is, spelled the way the API spells it.
public struct Identity: Codable, Equatable, Hashable, Sendable {
    /// Your own user id. At most 120 characters.
    public var id: String?
    public var email: String?
    /// At most 150 characters.
    public var name: String?
    public var metadata: [String: MetadataValue]?
    /// Hex HMAC-SHA256 of `id`, keyed with the identity secret. Computed on your server, never in the app.
    public var userHash: String?

    public init(
        id: String? = nil, email: String? = nil, name: String? = nil,
        metadata: [String: MetadataValue]? = nil, userHash: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.metadata = metadata
        self.userHash = userHash
    }
}

public enum Delivery: String, Codable, Sendable {
    case pending, sent, failed
}

/// A message as the app shows it, including ones that have not reached the server yet.
public struct ChatMessage: Equatable, Sendable, Identifiable {
    /// The server's id once there is one, and the client id until then.
    public var id: String
    public var author: Author
    public var authorName: String
    public var authorAvatarUrl: String
    public var text: String
    /// Whether `text` is markdown. False only for old messages whose text was flattened from HTML.
    public var markdown: Bool
    public var attachments: [ApiAttachment]
    public var createdAt: String
    public var delivery: Delivery
    /// The id this client made up, so a retry is recognised as the same message.
    public var clientMessageId: String?

    public init(
        id: String, author: Author, authorName: String = "", authorAvatarUrl: String = "",
        text: String, markdown: Bool = true, attachments: [ApiAttachment] = [], createdAt: String,
        delivery: Delivery, clientMessageId: String? = nil
    ) {
        self.id = id
        self.author = author
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
        self.text = text
        self.markdown = markdown
        self.attachments = attachments
        self.createdAt = createdAt
        self.delivery = delivery
        self.clientMessageId = clientMessageId
    }
}

public struct ChatState: Equatable, Sendable {
    /// `unconfigured` means no support surface right now: the widget is off, or hidden outside hours.
    public enum Status: String, Sendable {
        case idle, loading, ready, unconfigured, error
    }

    public struct Conversation: Equatable, Sendable {
        public var ticketId: String
        public var ticketReference: String
        public var status: String
        public var subject: String
    }

    public var status: Status = .idle
    public var config: WidgetConfig?
    public var conversation: Conversation?
    public var messages: [ChatMessage] = []
    /// The agent writing a reply right now.
    public var typing: Typing?
    /// Agent messages that arrived since the visitor last had the conversation open.
    public var unreadCount: Int = 0
    /// True between a failed request and the next one that works.
    public var offline: Bool = false
    /// The last thing that went wrong, in words a person could be shown.
    public var error: String?

    public init() {}
}
