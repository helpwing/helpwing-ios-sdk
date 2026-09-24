import Foundation

/// The project's own words (heading, greeting, offline message) in the app's language.
/// The chat's chrome ("Send", …) is not here: that is `SupportLabels`, which the app owns.
public enum Copy {
    public enum Field: String, Sendable {
        case title
        case greeting
        case offlineMessage = "offline_message"
    }

    /// The project's translation for `locale`, else what it wrote without one. `ru-RU` finds `ru`.
    public static func forLocale(_ config: WidgetConfig?, _ field: Field, locale: String? = nil) -> String {
        guard let config else { return "" }
        let matched = match(locale, available: Array(config.translations.keys))
        if !matched.isEmpty, let translated = config.translations[matched]?[field.rawValue], !translated.isEmpty {
            return translated
        }
        switch field {
        case .title: return config.title
        case .greeting: return config.greeting
        case .offlineMessage: return config.offlineMessage
        }
    }

    /// The available tag `locale` asks for, falling back from `pt-BR` to `pt`.
    public static func match(_ locale: String?, available: [String]) -> String {
        let tag = (locale ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if tag.isEmpty { return "" }
        if available.contains(tag) { return tag }
        let primary = String(tag.split(separator: "-").first ?? "")
        return available.contains(primary) ? primary : ""
    }
}
