#if canImport(SwiftUI)
import SwiftUI

/// The round button that opens the chat, with the unread count on it.
/// Hidden while the chat is open, and when the project has no chat or turned it off for phones.
public struct SupportLauncher: View {
    @EnvironmentObject private var support: HelpwingSupport
    @Environment(\.colorScheme) private var device

    private let labels: SupportLabels

    public init(labels: SupportLabels = .default) {
        self.labels = labels
    }

    public var body: some View {
        if support.isReady && !support.isOpen && support.config?.showOnMobile != false {
            let theme = support.theme(device: device)
            Button(action: support.open) {
                Text(labels.launcher)
                    .font(theme.font(15, weight: .semibold))
                    .foregroundColor(Color(hex: theme.onAccent))
                    .padding(.horizontal, 20)
                    .frame(minWidth: 56, minHeight: 56)
                    .background(Color(hex: theme.accent))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .overlay(badge(theme), alignment: .topTrailing)
            .accessibilityLabel(Text(labels.launcher))
        }
    }

    @ViewBuilder
    private func badge(_ theme: HelpwingTheme) -> some View {
        let count = support.unreadCount
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(theme.font(12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 22)
                .background(Capsule().fill(Color(hex: theme.danger)))
                .overlay(Capsule().stroke(Color(hex: theme.background), lineWidth: 2))
                .offset(x: 4, y: -4)
        }
    }
}

/// The chat in a sheet: a header with the project's name and a close button, over `SupportChat`.
public struct SupportModal: View {
    @EnvironmentObject private var support: HelpwingSupport
    @Environment(\.colorScheme) private var device

    private let title: String?
    private let labels: SupportLabels
    private let onClose: (() -> Void)?

    /// - Parameters:
    ///   - title: Defaults to the project's heading, then its name.
    ///   - onClose: Defaults to `support.close()`.
    public init(title: String? = nil, labels: SupportLabels = .default, onClose: (() -> Void)? = nil) {
        self.title = title
        self.labels = labels
        self.onClose = onClose
    }

    public var body: some View {
        let theme = support.theme(device: device)
        let heading = title ?? (support.copy.title.isEmpty ? support.config?.projectName ?? "" : support.copy.title)
        SupportChat(labels: labels) {
            VStack(spacing: 0) {
                HStack {
                    Text(heading)
                        .font(theme.font(17, weight: .semibold))
                        .foregroundColor(Color(hex: theme.text))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Button(labels.close) { (onClose ?? support.close)() }
                        .font(theme.font(16, weight: .medium))
                        .foregroundColor(Color(hex: theme.accent))
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Rectangle().fill(Color(hex: theme.border)).frame(height: 0.5)
            }
        }
    }
}

extension View {
    /// Float a `SupportLauncher` in the corner the project chose, `offset` points in from the edges.
    public func supportLauncher(labels: SupportLabels = .default, offset: CGFloat = 24) -> some View {
        modifier(LauncherOverlay(labels: labels, offset: offset))
    }

    /// Present `SupportModal` as a sheet whenever `support.open()` is called.
    public func supportSheet(title: String? = nil, labels: SupportLabels = .default) -> some View {
        modifier(SupportSheet(title: title, labels: labels))
    }
}

private struct LauncherOverlay: ViewModifier {
    @EnvironmentObject private var support: HelpwingSupport
    let labels: SupportLabels
    let offset: CGFloat

    func body(content: Content) -> some View {
        let left = support.config?.launcherPosition == "bottom_left"
        content.overlay(alignment: left ? .bottomLeading : .bottomTrailing) {
            SupportLauncher(labels: labels).padding(offset)
        }
    }
}

private struct SupportSheet: ViewModifier {
    @EnvironmentObject private var support: HelpwingSupport
    let title: String?
    let labels: SupportLabels

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { support.isOpen }, set: { if !$0 { support.close() } })) {
            SupportModal(title: title, labels: labels).environmentObject(support)
        }
    }
}
#endif
