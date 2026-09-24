#if canImport(UIKit) && canImport(SwiftUI) && !os(watchOS)
import SwiftUI
import UIKit

/// The chat for a UIKit app: present it modally, or push it with `showsHeader: false`.
public final class SupportViewController: UIHostingController<AnyView> {
    private let support: HelpwingSupport

    /// - Parameter showsHeader: Draw the title and close button. Off when a navigation bar already does.
    public init(support: HelpwingSupport, title: String? = nil, labels: SupportLabels = .default, showsHeader: Bool = true) {
        self.support = support
        super.init(rootView: AnyView(EmptyView()))
        let close: () -> Void = { [weak self] in self?.dismiss(animated: true) }
        rootView = showsHeader
            ? AnyView(SupportModal(title: title, labels: labels, onClose: close).environmentObject(support))
            : AnyView(SupportChat(labels: labels).environmentObject(support))
        self.title = title ?? support.config?.projectName
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

extension HelpwingSupport {
    /// Present the chat modally over `presenter`.
    public func present(from presenter: UIViewController, title: String? = nil, labels: SupportLabels = .default) {
        let controller = SupportViewController(support: self, title: title, labels: labels)
        controller.modalPresentationStyle = .pageSheet
        presenter.present(controller, animated: true)
    }
}
#endif
