import Foundation
import Combine

/// The conversation, with no opinion about how it is drawn.
///
/// It polls (5s while read, 30s otherwise, never in the background), retries sends by
/// idempotency key, never retries a start by itself, and tells the server when the visitor is reading.
@MainActor
public final class HelpwingChat: ObservableObject {
    public nonisolated static let defaultPollInterval: TimeInterval = 5
    public nonisolated static let defaultBackgroundPollInterval: TimeInterval = 30

    @Published public private(set) var state = ChatState()

    private let transport: Transport
    private let store: SessionStore
    private let pollInterval: TimeInterval
    private let backgroundPollInterval: TimeInterval
    private let uuid: () -> String
    private let locale: String
    private let timezone: String

    private var listeners: [UUID: (ChatState) -> Void] = [:]
    private var session: StoredSession?
    private var identity: Identity?
    private var present = false
    private var active = true
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var flushing = false
    private var destroyed = false

    /// - Parameters:
    ///   - apiUrl: The host that serves `/widget.js`, e.g. `https://api.helpwing.app`.
    ///   - projectKey: The public `pk_…` key. Safe to ship in an app.
    ///   - backgroundPollInterval: While the chat is closed but the app is open. Zero stops it.
    public init(
        apiUrl: String,
        projectKey: String,
        storage: HelpwingStorage = UserDefaultsStorage(),
        pollInterval: TimeInterval = HelpwingChat.defaultPollInterval,
        backgroundPollInterval: TimeInterval = HelpwingChat.defaultBackgroundPollInterval,
        locale: String? = nil,
        timezone: String? = nil,
        http: HelpwingHTTP = URLSessionHTTP(),
        uuid: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        transport = Transport(apiUrl: apiUrl, projectKey: projectKey, http: http)
        store = SessionStore(storage: storage, projectKey: projectKey)
        self.pollInterval = pollInterval
        self.backgroundPollInterval = backgroundPollInterval
        self.uuid = uuid
        self.locale = locale ?? ""
        self.timezone = timezone ?? ""
    }

    // MARK: - public

    /// Called immediately with the state, then on every change. Returns the unsubscribe.
    @discardableResult
    public func subscribe(_ listener: @escaping (ChatState) -> Void) -> @MainActor () -> Void {
        let id = UUID()
        listeners[id] = listener
        listener(state)
        return { [weak self] in self?.listeners[id] = nil }
    }

    /// Load the config and any stored conversation. Safe to call again; never throws.
    public func start() async {
        patch {
            $0.status = $0.config != nil ? $0.status : .loading
            $0.error = nil
        }
        do {
            let config = try await transport.config()
            patch {
                $0.config = config
                $0.offline = false
            }
            if !config.isEnabled || (!config.isOnline && config.hideWhenClosed) {
                patch { $0.status = .unconfigured }
                return
            }
        } catch {
            fail(error)
            return
        }

        session = store.read()
        if session != nil { await restore() }
        patch { $0.status = .ready }
        schedule()
    }

    /// Say who the visitor is, now or for the conversation not yet started. `nil` on sign-out.
    /// Naming somebody else drops the conversation on screen: it belongs to whoever opened it.
    public func identify(_ identity: Identity?) async {
        let key = HelpwingChat.identityKey(identity)
        if !key.isEmpty, let current = session, !current.identityKey.isEmpty, key != current.identityKey {
            dropConversation()
        }
        self.identity = identity
        guard let identity, let current = session else { return }
        do {
            try await transport.identify(ticketId: current.ticketId, token: current.token, identity: identity)
            current.identityKey = key
            persist(current)
        } catch let error as HelpwingError where error.status == 409 {
            if session === current { dropConversation() }
        } catch {
            // Never surfaced: a name that failed to attach is not worth an error on screen.
            note(error)
        }
    }

    /// Send a message, drawing it before it has gone anywhere. `email` is only read when opening.
    public func send(_ text: String, email: String? = nil) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        let pending = PendingMessage(clientMessageId: uuid(), text: body, createdAt: HelpwingChat.now())
        patch {
            $0.messages.append(HelpwingChat.draw(pending))
            $0.error = nil
        }

        guard let current = session else {
            await open(pending, email: email ?? "")
            return
        }
        current.pending.append(pending)
        persist(current)
        await flush()
    }

    /// Try a failed message again. On a new conversation this may open a second one, so only a person asks.
    public func retry(_ clientMessageId: String) async {
        guard let failed = state.messages.first(where: { $0.clientMessageId == clientMessageId && $0.delivery == .failed })
        else { return }

        let pending = PendingMessage(clientMessageId: clientMessageId, text: failed.text, createdAt: failed.createdAt)
        var retried = failed
        retried.delivery = .pending
        replace(clientMessageId, with: retried)

        guard let current = session else {
            await open(pending, email: "")
            return
        }
        if !current.pending.contains(where: { $0.clientMessageId == clientMessageId }) {
            current.pending.append(pending)
            persist(current)
        }
        await flush()
    }

    /// Whether the visitor is looking at the conversation. Decides the poll rate and whether replies are mailed.
    public func setPresent(_ present: Bool) {
        guard self.present != present else { return }
        self.present = present
        if present {
            markRead()
            tick()
        } else {
            schedule()
        }
    }

    /// Whether the app is in the foreground. Polling stops entirely when it is not.
    public func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active { tick() } else { clearTimer() }
    }

    /// Clear the unread badge.
    public func markRead() {
        if let current = session {
            current.lastReadCursor = current.cursor
            persist(current)
        }
        if state.unreadCount != 0 { patch { $0.unreadCount = 0 } }
    }

    /// Ask now rather than at the next tick. Returns after a request that started no earlier than this call.
    public func refresh() async {
        if let running = inFlight { await running.value }
        await tick()?.value
    }

    /// Forget the visitor and the conversation on this device. For sign-out on a shared device.
    public func reset() async {
        identity = nil
        dropConversation()
    }

    /// Stop everything. The object is not usable afterwards.
    public func destroy() {
        destroyed = true
        clearTimer()
        listeners.removeAll()
    }

    // MARK: - the conversation

    private func dropConversation() {
        clearTimer()
        session = nil
        store.clear()
        patch {
            $0.conversation = nil
            $0.messages = []
            $0.typing = nil
            $0.unreadCount = 0
            $0.error = nil
        }
        schedule()
    }

    private func restore() async {
        guard let current = session else { return }
        do {
            let conversation = try await transport.conversation(ticketId: current.ticketId, token: current.token)
            current.cursor = conversation.cursor
            persist(current)
            adopt(conversation, replaceTranscript: true)
            await flush()
        } catch {
            handle(error)
        }
    }

    private func open(_ pending: PendingMessage, email: String) async {
        do {
            let conversation = try await transport.start(
                bodyText: pending.text, identity: identity, email: email, locale: locale, timezone: timezone
            )
            let opened = StoredSession(
                token: conversation.visitorToken,
                ticketId: conversation.ticketId,
                identityKey: HelpwingChat.identityKey(identity),
                cursor: conversation.cursor,
                lastReadCursor: conversation.cursor,
                pending: []
            )
            session = opened
            persist(opened)
            // The start endpoint takes no client id, so the early copy is dropped by hand.
            forget(pending.clientMessageId)
            adopt(conversation, replaceTranscript: true)
            patch { $0.offline = false }
            schedule()
        } catch {
            var failed = HelpwingChat.draw(pending)
            failed.delivery = .failed
            replace(pending.clientMessageId, with: failed)
            fail(error, keepStatus: true)
        }
    }

    /// Send the queue oldest first, stopping at the first one that cannot go, so order is kept.
    private func flush() async {
        guard let current = session, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let next = current.pending.first {
            do {
                let conversation = try await transport.send(
                    ticketId: current.ticketId, token: current.token,
                    bodyText: next.text, clientMessageId: next.clientMessageId
                )
                current.pending.removeAll { $0.clientMessageId == next.clientMessageId }
                persist(current)
                forget(next.clientMessageId)
                if session === current { adopt(conversation) }
                patch { $0.offline = false }
            } catch {
                if handleSendFailure(error, next, in: current) { break }
            }
        }
    }

    /// A network error keeps the message queued; an answered refusal marks it failed. Returns whether to stop.
    private func handleSendFailure(_ error: Error, _ message: PendingMessage, in current: StoredSession) -> Bool {
        if let error = error as? HelpwingError, error.isGone {
            handle(error)
            return true
        }
        if let error = error as? HelpwingError, error.isNetwork {
            patch { $0.offline = true }
            return true
        }
        current.pending.removeAll { $0.clientMessageId == message.clientMessageId }
        persist(current)
        var failed = HelpwingChat.draw(message)
        failed.delivery = .failed
        replace(message.clientMessageId, with: failed)
        fail(error, keepStatus: true)
        return false
    }

    // MARK: - polling

    private func schedule() {
        clearTimer()
        guard !destroyed, session != nil, active else { return }
        let interval = present ? pollInterval : backgroundPollInterval
        guard interval > 0 else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    /// One round: send what is waiting, then ask what arrived. Never two at once.
    @discardableResult
    private func tick() -> Task<Void, Never>? {
        if destroyed || inFlight != nil || session == nil || !active { return inFlight }
        let round = Task { [weak self] in
            guard let self else { return }
            await self.flush()
            await self.poll()
            self.inFlight = nil
            self.schedule()
        }
        inFlight = round
        return round
    }

    private func poll() async {
        guard let current = session else { return }
        do {
            let updates = try await transport.updates(
                ticketId: current.ticketId, token: current.token, since: current.cursor, present: present
            )
            guard session === current else { return }
            current.cursor = updates.cursor
            persist(current)
            merge(updates.messages, typing: .some(updates.typing), status: updates.status)
            if state.offline { patch { $0.offline = false } }
        } catch {
            handle(error)
        }
    }

    // MARK: - state

    private func adopt(_ conversation: ApiConversation, replaceTranscript: Bool = false) {
        patch {
            $0.conversation = ChatState.Conversation(
                ticketId: conversation.ticketId,
                ticketReference: conversation.ticketReference,
                status: conversation.status,
                subject: conversation.subject
            )
            // Whatever is still trying to be sent survives a whole-transcript reload.
            if replaceTranscript { $0.messages = $0.messages.filter { $0.delivery != .sent } }
        }
        merge(conversation.messages, typing: .some(conversation.typing), status: conversation.status)
    }

    /// Fold server messages in, replacing any copy drawn early. `typing` of `.none` leaves it as is.
    private func merge(_ incoming: [ApiMessage], typing: Typing??, status: String?) {
        var order: [String] = []
        var byId: [String: ChatMessage] = [:]
        for message in state.messages {
            if byId[message.id] == nil { order.append(message.id) }
            byId[message.id] = message
        }
        var drawnEarly = Set<String>()
        for message in incoming {
            if !message.clientMessageId.isEmpty { drawnEarly.insert(message.clientMessageId) }
            if byId[message.id] == nil { order.append(message.id) }
            byId[message.id] = HelpwingChat.received(message)
        }

        let messages = order.enumerated()
            .compactMap { index, id -> (Int, ChatMessage)? in
                guard let message = byId[id] else { return nil }
                if let clientId = message.clientMessageId, drawnEarly.contains(clientId), message.delivery != .sent {
                    return nil
                }
                return (index, message)
            }
            .sorted { $0.1.createdAt == $1.1.createdAt ? $0.0 < $1.0 : $0.1.createdAt < $1.1.createdAt }
            .map(\.1)

        patch {
            $0.messages = messages
            if let typing { $0.typing = typing }
            if let status, !status.isEmpty, $0.conversation != nil { $0.conversation?.status = status }
        }
        recount()
    }

    private func forget(_ clientMessageId: String) {
        patch { $0.messages.removeAll { $0.clientMessageId == clientMessageId && $0.delivery != .sent } }
    }

    private func replace(_ clientMessageId: String, with message: ChatMessage) {
        patch {
            $0.messages = $0.messages.map {
                $0.clientMessageId == clientMessageId && $0.delivery != .sent ? message : $0
            }
        }
    }

    /// Agent messages since the visitor last looked. Zero while they are looking.
    private func recount() {
        if present {
            markRead()
            return
        }
        let since = session?.lastReadCursor ?? ""
        let unread = state.messages.filter { $0.author == .agent && $0.delivery == .sent && $0.createdAt > since }.count
        if unread != state.unreadCount { patch { $0.unreadCount = unread } }
    }

    private func patch(_ change: (inout ChatState) -> Void) {
        var next = state
        change(&next)
        state = next
        for listener in listeners.values { listener(next) }
    }

    private func persist(_ current: StoredSession) {
        if session === current { store.write(current) }
    }

    // MARK: - failure

    /// A conversation the server no longer knows is let go of; anything else is noted.
    private func handle(_ error: Error) {
        if let error = error as? HelpwingError, error.isGone {
            session = nil
            store.clear()
            clearTimer()
            patch {
                $0.conversation = nil
                $0.messages = []
                $0.typing = nil
                $0.unreadCount = 0
            }
            return
        }
        note(error)
    }

    private func note(_ error: Error) {
        if let error = error as? HelpwingError, error.isNetwork {
            if !state.offline { patch { $0.offline = true } }
            return
        }
        let message = (error as? HelpwingError)?.message ?? "Something went wrong."
        patch { $0.error = message }
    }

    private func fail(_ error: Error, keepStatus: Bool = false) {
        note(error)
        if !keepStatus && state.status != .ready { patch { $0.status = .error } }
    }

    private func clearTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - plumbing

    /// Who an identity names, as one comparable string: the id when there is one.
    static func identityKey(_ identity: Identity?) -> String {
        let id = (identity?.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return "id:\(id)" }
        let email = (identity?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.isEmpty ? "" : "email:\(email)"
    }

    private static func draw(_ pending: PendingMessage) -> ChatMessage {
        ChatMessage(
            id: pending.clientMessageId, author: .customer, text: pending.text, markdown: true,
            createdAt: pending.createdAt, delivery: .pending, clientMessageId: pending.clientMessageId
        )
    }

    private static func received(_ message: ApiMessage) -> ChatMessage {
        ChatMessage(
            id: message.id,
            author: message.author,
            authorName: message.authorName,
            authorAvatarUrl: message.authorAvatarUrl,
            text: message.bodyText.isEmpty ? HTMLText.plain(message.bodyHtml) : message.bodyText,
            markdown: !message.bodyText.isEmpty,
            attachments: message.attachments,
            createdAt: message.createdAt,
            delivery: .sent,
            clientMessageId: message.clientMessageId.isEmpty ? nil : message.clientMessageId
        )
    }

    /// ISO 8601 in UTC with milliseconds, the same shape the server's timestamps sort against.
    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

/// An HTML body flattened to text, for an old message stored without markdown.
enum HTMLText {
    static func plain(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html
        let rules: [(String, String)] = [
            (#"<\s*br\s*/?\s*>"#, "\n"),
            (#"<\s*/\s*(p|div|li|tr|h[1-6])\s*>"#, "\n"),
            (#"<[^>]*>"#, ""),
            ("&nbsp;", " "),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&amp;", "&"),
            (#"\n{3,}"#, "\n\n"),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(
                of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive]
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
