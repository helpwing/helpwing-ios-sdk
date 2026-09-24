#if canImport(SwiftUI)
import SwiftUI

/// The conversation as a screen. Being on screen is what marks the visitor as reading,
/// which stops an agent's reply also being emailed to them.
public struct SupportChat<Header: View>: View {
    @EnvironmentObject private var support: HelpwingSupport
    @Environment(\.colorScheme) private var device

    private let labels: SupportLabels
    private let header: Header

    /// - Parameter header: Drawn above the transcript; a title with a close button usually goes here.
    public init(labels: SupportLabels = .default, @ViewBuilder header: () -> Header) {
        self.labels = labels
        self.header = header()
    }

    public var body: some View {
        let theme = support.theme(device: device)
        content(theme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: theme.background).ignoresSafeArea())
            .onAppear { support.chat.setPresent(true) }
            .onDisappear { support.chat.setPresent(false) }
    }

    @ViewBuilder
    private func content(_ theme: HelpwingTheme) -> some View {
        switch support.state.status {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView().tint(Color(hex: theme.accent))
                muted(labels.loading, theme)
            }
            .padding(24)
        case .unconfigured:
            muted(labels.unavailable, theme).padding(24)
        case .ready, .error:
            conversation(theme)
        }
    }

    private func conversation(_ theme: HelpwingTheme) -> some View {
        let config = support.config
        // An address is asked for only until there is a conversation to reply to.
        let askForEmail = (config?.requireEmail ?? false) && support.state.conversation == nil

        return VStack(spacing: 0) {
            header

            if config?.showAgentAvailability == true {
                VStack(spacing: 0) {
                    Text(config?.isOnline == true ? labels.online : labels.away)
                        .font(theme.font(12))
                        .foregroundColor(Color(hex: theme.mutedText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Rectangle().fill(Color(hex: theme.border)).frame(height: 0.5)
                }
            }

            if support.offline {
                Text(labels.offline)
                    .font(theme.font(12))
                    .foregroundColor(Color(hex: theme.mutedText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: theme.surface))
            }

            transcript(theme)

            if let typing = support.typing {
                Text(labels.typing(typing.name))
                    .font(theme.font(12))
                    .foregroundColor(Color(hex: theme.mutedText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            Composer(theme: theme, labels: labels, askForEmail: askForEmail) { text, email in
                Task { await support.send(text, email: email.isEmpty ? nil : email) }
            }

            if config?.showBranding == true, let url = URL(string: "https://helpwing.app") {
                Link(destination: url) {
                    Text(labels.branding)
                        .font(theme.font(11))
                        .foregroundColor(Color(hex: theme.mutedText))
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func transcript(_ theme: HelpwingTheme) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if support.messages.isEmpty {
                    greeting(theme)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(support.messages) { message in
                            MessageBubble(message: message, theme: theme, labels: labels) { id in
                                Task { await support.retry(id) }
                            }
                            .id(message.id)
                        }
                        Color.clear.frame(height: 1).id(SupportChatAnchor.bottom)
                    }
                    .padding(.vertical, 12)
                }
            }
            .onAppear { proxy.scrollTo(SupportChatAnchor.bottom, anchor: .bottom) }
            // Only when something arrived: somebody scrolled up to read is not asking to be moved.
            .onChange(of: support.messages.count) { _ in
                withAnimation { proxy.scrollTo(SupportChatAnchor.bottom, anchor: .bottom) }
            }
        }
    }

    private func greeting(_ theme: HelpwingTheme) -> some View {
        let copy = support.copy
        let text = support.config?.isOnline == false && !copy.offlineMessage.isEmpty ? copy.offlineMessage : copy.greeting
        return Text(text)
            .font(theme.font(15))
            .foregroundColor(Color(hex: theme.mutedText))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(32)
    }

    private func muted(_ text: String, _ theme: HelpwingTheme) -> some View {
        Text(text)
            .font(theme.font(14))
            .foregroundColor(Color(hex: theme.mutedText))
            .multilineTextAlignment(.center)
    }
}

extension SupportChat where Header == EmptyView {
    public init(labels: SupportLabels = .default) {
        self.init(labels: labels) { EmptyView() }
    }
}

private enum SupportChatAnchor: Hashable {
    case bottom
}

/// The box the visitor writes in, and the address box above it when the project asks for one.
struct Composer: View {
    let theme: HelpwingTheme
    let labels: SupportLabels
    let askForEmail: Bool
    let onSend: (String, String) -> Void

    @State private var text = ""
    @State private var email = ""

    private var ready: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!askForEmail || !email.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(spacing: 8) {
            if askForEmail {
                field(TextField("", text: $email), placeholder: labels.emailPlaceholder, show: email.isEmpty)
                    .modifier(EmailField())
            }
            HStack(alignment: .bottom, spacing: 8) {
                messageField
                Button(action: submit) {
                    Text(labels.send)
                        .font(theme.font(15, weight: .semibold))
                        .foregroundColor(Color(hex: theme.onAccent))
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(Color(hex: theme.accent))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
                .accessibilityLabel(Text(labels.send))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(hex: theme.background))
        .overlay(Rectangle().fill(Color(hex: theme.border)).frame(height: 0.5), alignment: .top)
    }

    @ViewBuilder
    private var messageField: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            field(TextField("", text: $text, axis: .vertical).lineLimit(1...5), placeholder: labels.placeholder, show: text.isEmpty)
        } else {
            field(TextField("", text: $text, onCommit: submit), placeholder: labels.placeholder, show: text.isEmpty)
        }
    }

    /// A rounded field with a placeholder drawn in the theme's muted colour.
    private func field<Field: View>(_ input: Field, placeholder: String, show: Bool) -> some View {
        ZStack(alignment: .leading) {
            if show {
                Text(placeholder)
                    .font(theme.font(15))
                    .foregroundColor(Color(hex: theme.mutedText))
                    .allowsHitTesting(false)
            }
            input
                .textFieldStyle(.plain)
                .font(theme.font(15))
                .foregroundColor(Color(hex: theme.text))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background(Color(hex: theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func submit() {
        guard ready else { return }
        onSend(text, email.trimmingCharacters(in: .whitespaces))
        text = ""
    }
}

private struct EmailField: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        #else
        content.disableAutocorrection(true)
        #endif
    }
}
#endif
