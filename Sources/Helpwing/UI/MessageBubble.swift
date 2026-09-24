#if canImport(SwiftUI)
import SwiftUI

/// One message in the transcript.
public struct MessageBubble: View {
    private let message: ChatMessage
    private let theme: HelpwingTheme
    private let labels: SupportLabels
    private let onRetry: (String) -> Void

    public init(message: ChatMessage, theme: HelpwingTheme, labels: SupportLabels = .default, onRetry: @escaping (String) -> Void = { _ in }) {
        self.message = message
        self.theme = theme
        self.labels = labels
        self.onRetry = onRetry
    }

    private var mine: Bool { message.author == .customer }

    /// Pictures this body may show, by `Content-ID`.
    private var images: [String: String] {
        var map: [String: String] = [:]
        for attachment in message.attachments where !attachment.contentId.isEmpty && !attachment.url.isEmpty {
            map[attachment.contentId] = attachment.url
        }
        return map
    }

    public var body: some View {
        if message.author == .system {
            Text(message.text)
                .font(theme.font(12))
                .foregroundColor(Color(hex: theme.mutedText))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                HStack {
                    if mine { Spacer(minLength: 48) }
                    bubble
                    if !mine { Spacer(minLength: 48) }
                }
                if message.delivery == .pending {
                    Text(labels.sending)
                        .font(theme.font(11))
                        .foregroundColor(Color(hex: theme.mutedText))
                        .padding(.horizontal, 4)
                }
                if message.delivery == .failed {
                    Button {
                        if let id = message.clientMessageId { onRetry(id) }
                    } label: {
                        Text("\(labels.failed) \(labels.retry)")
                            .font(theme.font(11))
                            .foregroundColor(Color(hex: theme.danger))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var bubble: some View {
        let ink = mine ? theme.onAccent : theme.text
        return VStack(alignment: .leading, spacing: 2) {
            if !mine && !message.authorName.isEmpty {
                Text(message.authorName)
                    .font(theme.font(12, weight: .semibold))
                    .foregroundColor(Color(hex: theme.mutedText))
            }
            if message.markdown {
                // On the accent there is no quieter colour that stays readable, so muted is the ink.
                MarkdownView(message.text, theme: theme, color: ink, muted: mine ? theme.onAccent : theme.mutedText, images: images)
            } else {
                Text(message.text)
                    .font(theme.font(15))
                    .foregroundColor(Color(hex: ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A picture pasted into the body is already drawn there.
            ForEach(message.attachments.filter { !$0.isInline }) { attachment in
                attachmentRow(attachment, color: mine ? theme.onAccent : theme.mutedText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: mine ? theme.accent : theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(message.delivery == .pending ? 0.6 : 1)
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: ApiAttachment, color: String) -> some View {
        let label = Text(attachment.filename)
            .font(theme.font(13))
            .underline()
            .foregroundColor(Color(hex: color))
        if let url = URL(string: attachment.url), !attachment.url.isEmpty {
            Link(destination: url) { label }.padding(.top, 6)
        } else {
            label.padding(.top, 6)
        }
    }
}
#endif
