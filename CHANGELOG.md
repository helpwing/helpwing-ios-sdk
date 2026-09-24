# Changelog

Versions are immutable once tagged: SwiftPM resolves a tag straight from git, so `0.1.0`
is the release and nothing else publishes anything.

## 0.1.0

- **First release.** The Helpwing support chat for native iOS apps, as a Swift package with
  no dependencies. Speaks the same public widget API as `widget.js` and
  `@helpwing/react-native`, and behaves the same way:
  - `HelpwingChat`, the conversation with no UI: polling, an offline queue that survives
    the app being killed, idempotent retries, identity, unread counts against the server's
    cursor.
  - SwiftUI views: `SupportChat`, `SupportLauncher` / `.supportLauncher()`,
    `SupportModal` / `.supportSheet()`, `MessageBubble`, `MarkdownView`.
  - `SupportViewController` for UIKit apps.
  - The project's accent, colour scheme and translated copy from the dashboard; any colour
    and the typeface overridable; every string of the chat's own chrome a label.
  - Agent replies rendered from markdown (bold, italic, code, links, lists, quotes,
    headings, fenced code, rules, tables, and pictures pasted into an email body).
