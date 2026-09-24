# Helpwing for iOS

The [Helpwing](https://helpwing.app) support chat for native iOS apps, in SwiftUI or UIKit.
App chat, website chat and email tickets land in the same inbox.

- Drop-in launcher, sheet and chat screen, or a `HelpwingChat` to draw your own
- Themed from your project's accent colour, or overridden to match your design system
- Every string is a label, so it speaks whatever language your app does
- Survives tunnels and app kills: messages queue, persist and retry
- A Swift package with no dependencies. iOS 15+, and macOS 12+ for the core

## Install

In Xcode, **File → Add Package Dependencies…** and paste the repository URL, or in
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/helpwing/helpwing-ios-sdk.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "Helpwing", package: "helpwing-ios-sdk")]),
]
```

## Setup

```swift
import Helpwing
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var support = HelpwingSupport(
        apiUrl: "https://api.helpwing.app",
        projectKey: "pk_live_..."
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .supportLauncher()
                .supportSheet()
                .helpwing(support)
        }
    }
}
```

The project key is public. It is the same one the website snippet carries in
`data-project`, and shipping it in an app bundle is expected.

`apiUrl` is whichever host serves `/widget.js`, because that is the host `/widget/` is
routed on.

The conversation is kept in `UserDefaults` under `helpwing:<project key>`. Pass
`storage:` for anything else: the Keychain, an App Group's defaults, or `MemoryStorage()`
in a test. `HelpwingStorage` is three methods.

### UIKit

```swift
let support = HelpwingSupport(apiUrl: "https://api.helpwing.app", projectKey: "pk_live_...")

// from any view controller
support.present(from: self)

// or push it, under a navigation bar that already has a title and a back button
navigationController?.pushViewController(
    SupportViewController(support: support, showsHeader: false), animated: true
)
```

## Your own screen instead

The launcher and the sheet are conveniences. An app with its own "Help" row in a settings
list wants neither:

```swift
struct HelpRow: View {
    @EnvironmentObject var support: HelpwingSupport

    var body: some View {
        // Being on screen is what marks the visitor as reading.
        NavigationLink(destination: SupportChat().navigationTitle("Support")) {
            Label("Support", systemImage: "questionmark.bubble")
                .badge(support.unreadCount)
        }
    }
}
```

Everything is on `HelpwingSupport`: `state`, `messages`, `unreadCount`, `typing`,
`offline`, `config`, `copy`, `theme(device:)`, `send`, `retry`, `refresh`, `reset`,
`identity` and the `chat` client itself. Draw whatever you like against it. The views here
are one answer, not the only one.

## Telling us who the visitor is

```swift
support.identity = Identity(id: user.id, email: user.email, name: user.name, userHash: user.supportHash)
```

Applied whenever it changes, including to a conversation that started before anyone signed
in. A visitor who asked something anonymously and then signed in is the ordinary case, and
the conversation moves to their customer record when they do.

**`userHash` is an HMAC-SHA256 of the user id, keyed with your project's identity secret,
and your server computes it.** An app bundle is a zip file with your code in it; a secret
shipped inside one is not a secret. Fetch the hash from your own API alongside the rest of
the signed-in user, the way you would a session token.

With identity verification turned on in the dashboard, an unproved claim is not refused.
It buys nothing: the visitor gets a customer record of their own, and what they claimed is
kept where an agent can see it without the profile implying anybody vouched for it.

On sign-out, `support.identity = nil` stops the *next* conversation being attributed to
whoever just left. `await support.reset()` also forgets the conversation itself, which is
what you want on a shared device.

Signing straight in as somebody else needs neither. A conversation belongs to whoever
opened it: when the identity changes from A to B, A's conversation is dropped from the
device and B opens their own. The server draws the same line and refuses to move a
conversation between two identified customers.

## Text

Two kinds of string, and they come from different places.

**The chat's own chrome**, like "Send" and "Write a message…". No translations ship with
this package; every string is a label:

```swift
SupportChat(labels: SupportLabels(placeholder: "Écrivez un message…", send: "Envoyer"))
```

`SupportLabels()` shows the whole list with its defaults. This is deliberate: your app
knows what language it is in and already has a way to say so, and shipping a dictionary of
our own would mean deciding which of two translation systems wins on one screen.

**What the project wrote**: the header, the greeting and the offline message. Those are
translated in the dashboard under **Chat widget → Appearance**, and picked by the `locale`
you pass. It defaults to the device's preferred language:

```swift
HelpwingSupport(apiUrl: …, projectKey: …, locale: "ru")
```

`ru-RU` finds `ru`, and a language the project has not translated falls back to what it
wrote without one, never to a stock line of ours. `SupportChat` draws the greeting and the
offline message; read them yourself from `support.copy` if you draw your own empty state.
`copy.title` is there too, blank when the project has written none.

## Colours

The project picks an accent in the dashboard and everything else is worked out from it,
including whether text on top of it should be white or ink.

Light or dark comes from the same place, **Chat widget → Appearance → Colour scheme**, and
ships as `Auto`, which follows the device. Nothing to pass: the chat arrives in the
appearance your own screens are drawn in, and turns with them.

`dark` overrules both, for a screen that is not the one the device asked for:

```swift
support.dark = true     // dark whatever the phone says
support.dark = false    // light whatever it says
support.dark = nil      // back to the project's setting
```

An app with a design system of its own names only what differs:

```swift
HelpwingSupport(
    apiUrl: …, projectKey: …,
    dark: true,
    theme: .init(accent: "#c6ff3a", background: "#0a0a0b", surface: "#141517", fontFamily: "FiraSans-Regular")
)
```

`fontFamily` is a PostScript name, the one you would pass to `Font.custom`. Leaving it out
keeps the system font.

## Delivery, polling and offline

Handled for you, but worth knowing because it is what you will see:

- New messages are polled every 5 seconds while the chat is on screen and every 30 while
  it is not, so the unread badge stays honest. Polling stops entirely while the app is in
  the background. Both intervals are parameters.
- Sends are idempotent and retried automatically, so a request lost mid-tunnel does not
  produce a duplicate. Starting a brand new conversation is the exception: if its answer is
  lost it is shown as a failed send, and retrying it is the visitor's decision.
- Unsent messages are written to storage, so they go out on the next launch, in order,
  even if the process was killed.
- Unread counts are computed against the server's cursor, never the phone's clock.

## Operating hours

The project's **Settings → Operating hours** screen decides whether the chat greets a
visitor or offers its offline message: `support.config?.isOnline` is that answer, and
`SupportChat` already draws both. A project may also choose to disappear outside its hours
rather than show an offline message, and then `state.status` is `.unconfigured` while it
is closed. That is the same state a widget that was turned off reports, so an app that
handles one handles both.

## Markdown

Agents answer from a markdown composer, so a reply arrives formatted rather than as the
markers that made it: **bold**, _italic_, `code`, links, bulleted and numbered lists,
quotes, headings, fenced code, rules and tables. Nothing to turn on. `Markdown.parse`
produces plain data and `MarkdownView` draws it with SwiftUI's own `Text`. There is no
HTML anywhere in it, so nothing anybody typed can become markup.

`ChatMessage.markdown` says whether `text` is markdown. It is false only for a message
stored before inbound email was translated on the way in, whose `text` is the flattened
reading of its HTML. Printing `text` reads correctly either way.

A picture the visitor pasted into an email comes back as an `isInline` attachment, and the
body points at it by `contentId`: `![alt](cid:<contentId>)`. `MessageBubble` draws those
where they were written and leaves them out of the file list underneath. A body can only
show a picture that came with it. A remote image is shown as a link to it, and a `cid`
with no file behind it renders as its alt text.

Links open through SwiftUI's `openURL`, and only `http`, `https`, `mailto` and `tel` ever
become links. Anything else is printed as the words it was made of.

## What it does not do

- **Push notifications.** Nothing arrives while the app is closed. Ask for an email address
  (`require_email` on the widget settings screen) and a reply written while the visitor is
  away reaches them there, which is the same fallback the website chat has.
- **Attachments from the visitor.** The API has no endpoint for it yet. A file that came
  with a message is listed by filename, except a picture written into the body, which is
  drawn there.
- **One conversation on two devices.** A visitor token belongs to one installation, so a
  reinstall starts a new conversation.

## The chat without the views

`HelpwingChat` is the conversation and none of the UI. It is a `@MainActor`
`ObservableObject` whose `state` is `@Published`, and it imports no SwiftUI.

| | |
| --- | --- |
| `start()` | Load the config and whatever conversation is stored. Never throws. |
| `send(_:email:)` | Send, drawing the message before it has gone anywhere. |
| `retry(_:)` | Try a failed message again, by its `clientMessageId`. |
| `identify(_:)` | Say who the visitor is, now or later. `nil` on sign-out. |
| `setPresent(_:)` | Whether the conversation is in front of them. |
| `setActive(_:)` | Whether the app is in the foreground. |
| `markRead()` | Clear the unread count. |
| `refresh()` | Ask now rather than at the next tick. |
| `reset()` | Forget the visitor and the conversation on this device. For sign-out. |
| `subscribe(_:)` | Called immediately, then on every change. Returns the unsubscribe. |
| `destroy()` | Stop everything. |

Errors land in `state.error` rather than being thrown: there is nothing an app can usefully
do with an exception raised while it was drawing a button.

## Reference

| `HelpwingSupport(…)` | |
| --- | --- |
| `apiUrl` | Where the API lives. Required. |
| `projectKey` | `pk_…`. Required. |
| `storage` | Any `HelpwingStorage`. Default `UserDefaultsStorage()`. |
| `identity` | The signed-in user, or `nil`. Also a settable property. |
| `pollInterval` | While the chat is on screen, in seconds. Default 5. |
| `backgroundPollInterval` | While it is not. Default 30; `0` to stop. |
| `dark` | Force the dark palette on or off. `nil` lets the project's Colour scheme decide, and `Auto` follows the device. |
| `theme` | `HelpwingTheme.Overrides`: any colour, and the typeface, on top of the project's accent. |
| `locale` | Picks the project's translated copy and is sent when a conversation opens. Default: the device language. |
| `timezone` | Sent when a conversation opens, for the agent's benefit. Default: the device's. |
| `http` | Any `HelpwingHTTP`. Default `URLSessionHTTP()`. |

Views: `SupportChat`, `SupportLauncher`, `SupportModal`, `MessageBubble`, `MarkdownView`,
and the modifiers `.helpwing(_:)`, `.supportLauncher()`, `.supportSheet()`. UIKit:
`SupportViewController`. Also public: `HelpwingChat`, `HelpwingError`, `Markdown`,
`Copy`, `Palette`, `HelpwingTheme`, `SupportLabels`, `MemoryStorage`,
`UserDefaultsStorage`, and the API models.

## Development

```bash
swift build
swift test
xcodebuild -scheme Helpwing -destination 'generic/platform=iOS Simulator' build
```

## Links

- [Documentation](https://helpwing.app/docs/ios)
- [Issues](https://github.com/helpwing/helpwing-ios-sdk/issues)
- [Changelog](CHANGELOG.md)

MIT © Helpwing
