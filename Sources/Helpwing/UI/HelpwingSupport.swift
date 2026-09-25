#if canImport(SwiftUI)
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The project's heading, greeting and offline message, resolved against the app's locale.
public struct SupportCopy: Equatable, Sendable {
    /// Blank when the project wrote no heading; the screen title stays the app's to choose.
    public var title: String
    public var greeting: String
    public var offlineMessage: String
    /// Blank keeps the built-in "{name} is typing…" label. `{name}` is replaced by the agent's name.
    public var typingText: String
}

/// One chat for the app: owns the client, follows the app's foreground state, resolves the theme.
/// Put it in the environment with `.helpwing(_:)`; every view in this package reads it from there.
@MainActor
public final class HelpwingSupport: ObservableObject {
    public let chat: HelpwingChat
    /// Whether the modal chat is on screen.
    @Published public private(set) var isOpen = false
    /// Force dark on or off. `nil` lets the project's colour scheme decide, and `system` follows the device.
    @Published public var dark: Bool?
    /// Any colours, and the typeface, applied on top of the project's accent.
    @Published public var themeOverrides: HelpwingTheme.Overrides?
    /// The signed-in user, or `nil`. Applied whenever it changes.
    public var identity: Identity? {
        didSet {
            guard identity != oldValue else { return }
            let next = identity
            Task { await chat.identify(next) }
        }
    }
    public let locale: String?

    private var forward: AnyCancellable?
    private let observers = Observers()

    /// - Parameters:
    ///   - locale: Picks the project's translated copy and is sent when a conversation opens. Defaults to the device language.
    public init(
        apiUrl: String,
        projectKey: String,
        storage: HelpwingStorage = UserDefaultsStorage(),
        identity: Identity? = nil,
        pollInterval: TimeInterval = HelpwingChat.defaultPollInterval,
        backgroundPollInterval: TimeInterval = HelpwingChat.defaultBackgroundPollInterval,
        dark: Bool? = nil,
        theme: HelpwingTheme.Overrides? = nil,
        locale: String? = Locale.preferredLanguages.first,
        timezone: String? = TimeZone.current.identifier,
        http: HelpwingHTTP = URLSessionHTTP()
    ) {
        chat = HelpwingChat(
            apiUrl: apiUrl, projectKey: projectKey, storage: storage, pollInterval: pollInterval,
            backgroundPollInterval: backgroundPollInterval, locale: locale, timezone: timezone, http: http
        )
        self.identity = identity
        self.dark = dark
        self.themeOverrides = theme
        self.locale = locale
        forward = chat.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        observeLifecycle()

        let chat = chat
        Task {
            await chat.start()
            if let identity { await chat.identify(identity) }
        }
    }

    // MARK: state

    public var state: ChatState { chat.state }
    public var config: WidgetConfig? { chat.state.config }
    public var messages: [ChatMessage] { chat.state.messages }
    public var unreadCount: Int { chat.state.unreadCount }
    public var typing: Typing? { chat.state.typing }
    public var offline: Bool { chat.state.offline }
    /// The project has a widget and it is turned on.
    public var isReady: Bool { chat.state.status == .ready }

    public var copy: SupportCopy {
        SupportCopy(
            title: Copy.forLocale(config, .title, locale: locale),
            greeting: Copy.forLocale(config, .greeting, locale: locale),
            offlineMessage: Copy.forLocale(config, .offlineMessage, locale: locale),
            typingText: Copy.forLocale(config, .typingText, locale: locale)
        )
    }

    /// Whether to draw dark: the app's override, then the project's setting, then the device.
    public func isDark(device: ColorScheme) -> Bool {
        if let dark { return dark }
        switch config?.colorScheme ?? .system {
        case .dark: return true
        case .light: return false
        case .system: return device == .dark
        }
    }

    public func theme(device: ColorScheme) -> HelpwingTheme {
        Palette.forAccent(config?.accentColor, dark: isDark(device: device)).applying(themeOverrides)
    }

    // MARK: actions

    public func open() {
        isOpen = true
        chat.setPresent(true)
    }

    public func close() {
        isOpen = false
        chat.setPresent(false)
    }

    public func send(_ text: String, email: String? = nil) async { await chat.send(text, email: email) }
    public func retry(_ clientMessageId: String) async { await chat.retry(clientMessageId) }
    public func refresh() async { await chat.refresh() }
    /// Forget the conversation on this device. For signing out.
    public func reset() async {
        identity = nil
        await chat.reset()
    }

    private func observeLifecycle() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        let foreground = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.chat.setActive(true) }
        }
        let background = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.chat.setActive(false) }
        }
        observers.tokens = [foreground, background]
        #endif
    }
}

/// Notification tokens, removed when the owner goes away.
private final class Observers {
    var tokens: [NSObjectProtocol] = []
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

extension View {
    /// Make `support` available to every Helpwing view below this one.
    public func helpwing(_ support: HelpwingSupport) -> some View {
        environmentObject(support)
    }
}

extension Color {
    /// A `#rgb` / `#rrggbb` string as a colour. Anything unreadable is clear.
    init(hex: String) {
        guard let rgb = Palette.rgb(hex) else {
            self = .clear
            return
        }
        self = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension HelpwingTheme {
    /// The theme's typeface at `size`, or the system font when none was named.
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontFamily, !fontFamily.isEmpty {
            return Font.custom(fontFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}
#endif
