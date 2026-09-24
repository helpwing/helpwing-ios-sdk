import Foundation

/// Every string the chat's own chrome shows. No translations ship with the package: your app knows its language.
public struct SupportLabels {
    public var placeholder: String
    public var emailPlaceholder: String
    public var send: String
    public var sending: String
    public var failed: String
    public var retry: String
    public var offline: String
    public var online: String
    public var away: String
    public var typing: (String) -> String
    public var branding: String
    public var loading: String
    public var unavailable: String
    public var launcher: String
    public var close: String

    public init(
        placeholder: String = "Write a message…",
        emailPlaceholder: String = "Your email address",
        send: String = "Send",
        sending: String = "Sending…",
        failed: String = "Not sent.",
        retry: String = "Tap to try again",
        offline: String = "No connection. Your messages will be sent when it comes back.",
        online: String = "We are online",
        away: String = "We are away right now",
        typing: @escaping (String) -> String = { "\($0) is typing…" },
        branding: String = "Powered by Helpwing",
        loading: String = "Loading…",
        unavailable: String = "Support chat is not available right now.",
        launcher: String = "Chat",
        close: String = "Close"
    ) {
        self.placeholder = placeholder
        self.emailPlaceholder = emailPlaceholder
        self.send = send
        self.sending = sending
        self.failed = failed
        self.retry = retry
        self.offline = offline
        self.online = online
        self.away = away
        self.typing = typing
        self.branding = branding
        self.loading = loading
        self.unavailable = unavailable
        self.launcher = launcher
        self.close = close
    }

    public static var `default`: SupportLabels { SupportLabels() }
}
