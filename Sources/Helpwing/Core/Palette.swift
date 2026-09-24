import Foundation

/// The colours the chat draws with, as hex strings, plus an optional typeface.
public struct HelpwingTheme: Equatable, Sendable {
    public var accent: String
    public var onAccent: String
    public var background: String
    public var surface: String
    public var border: String
    public var text: String
    public var mutedText: String
    public var danger: String
    /// A PostScript font name. `nil` keeps the system font.
    public var fontFamily: String?

    public init(
        accent: String, onAccent: String, background: String, surface: String, border: String,
        text: String, mutedText: String, danger: String, fontFamily: String? = nil
    ) {
        self.accent = accent
        self.onAccent = onAccent
        self.background = background
        self.surface = surface
        self.border = border
        self.text = text
        self.mutedText = mutedText
        self.danger = danger
        self.fontFamily = fontFamily
    }

    /// Any subset of the theme, applied on top of what the project's accent works out to.
    public struct Overrides: Equatable, Sendable {
        public var accent: String?
        public var onAccent: String?
        public var background: String?
        public var surface: String?
        public var border: String?
        public var text: String?
        public var mutedText: String?
        public var danger: String?
        public var fontFamily: String?

        public init(
            accent: String? = nil, onAccent: String? = nil, background: String? = nil, surface: String? = nil,
            border: String? = nil, text: String? = nil, mutedText: String? = nil, danger: String? = nil,
            fontFamily: String? = nil
        ) {
            self.accent = accent
            self.onAccent = onAccent
            self.background = background
            self.surface = surface
            self.border = border
            self.text = text
            self.mutedText = mutedText
            self.danger = danger
            self.fontFamily = fontFamily
        }
    }

    public func applying(_ overrides: Overrides?) -> HelpwingTheme {
        guard let o = overrides else { return self }
        return HelpwingTheme(
            accent: o.accent ?? accent,
            onAccent: o.onAccent ?? onAccent,
            background: o.background ?? background,
            surface: o.surface ?? surface,
            border: o.border ?? border,
            text: o.text ?? text,
            mutedText: o.mutedText ?? mutedText,
            danger: o.danger ?? danger,
            fontFamily: o.fontFamily ?? fontFamily
        )
    }
}

/// Everything derived from the one accent the project picked, as `widget.js` derives it.
public enum Palette {
    public static let defaultAccent = "#2563eb"

    public static func forAccent(_ accent: String?, dark: Bool = false) -> HelpwingTheme {
        let chosen = accent.flatMap { expand($0) != nil ? $0 : nil } ?? defaultAccent
        if dark {
            return HelpwingTheme(
                accent: chosen, onAccent: readableOn(chosen), background: "#0b0f19", surface: "#1a2032",
                border: "#2a3346", text: "#f4f6fb", mutedText: "#98a2b3", danger: "#f97066"
            )
        }
        return HelpwingTheme(
            accent: chosen, onAccent: readableOn(chosen), background: "#ffffff", surface: "#f2f4f7",
            border: "#e4e7ec", text: "#101828", mutedText: "#667085", danger: "#d92d20"
        )
    }

    /// White or ink, whichever stays readable on `color`, by relative luminance.
    public static func readableOn(_ color: String) -> String {
        guard let rgb = rgb(color) else { return "#ffffff" }
        let channels = [rgb.red, rgb.green, rgb.blue].map { value -> Double in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        return luminance > 0.55 ? "#101828" : "#ffffff"
    }

    /// `#rgb` or `#rrggbb` as 0…1 channels, or `nil` when it is not a colour.
    public static func rgb(_ color: String) -> (red: Double, green: Double, blue: Double)? {
        guard let hex = expand(color), let value = UInt32(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255
        )
    }

    private static func expand(_ color: String) -> String? {
        var hex = color.replacingOccurrences(of: "#", with: "")
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        let valid = hex.count == 6 && hex.allSatisfy { $0.isHexDigit && $0.isASCII }
        return valid ? hex : nil
    }
}
