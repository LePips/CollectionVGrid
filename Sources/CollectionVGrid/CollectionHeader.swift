import SwiftUI

#if canImport(UIKit)
private typealias HeaderHostingController = UIHostingController<AnyView>
typealias HostingCollectionViewHeader = UICollectionReusableView
#elseif os(macOS)
private typealias HeaderHostingController = NSHostingController<AnyView>
final class HostingCollectionViewHeader: NSView, NSCollectionViewElement {}
#endif

/// One host for both measurement and display preserves header state across scrolling and reuse.
@MainActor
final class CollectionHeader {
    private let controller: HeaderHostingController
    private var cachedSize: CGSize?

    init(content: AnyView) {
        controller = HeaderHostingController(rootView: content)
        #if canImport(UIKit)
        controller.view.backgroundColor = nil
        controller.safeAreaRegions = []
        #endif
        controller.view.translatesAutoresizingMaskIntoConstraints = false
    }

    func update(content: AnyView) {
        controller.rootView = content
        invalidateSize()
    }

    func invalidateSize() {
        cachedSize = nil
    }

    func size(forWidth width: CGFloat) -> CGSize {
        guard width.isFiniteAndPositive else { return .zero }

        if let cachedSize, cachedSize.width == width {
            return cachedSize
        }
        let measured = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: nonnegativeFinite(measured.height))
        cachedSize = size
        return size
    }

    func attach(to view: HostingCollectionViewHeader) {
        #if canImport(UIKit)
        let content = controller.view!
        #else
        let content = controller.view
        #endif
        guard content.superview !== view else { return }

        content.removeFromSuperview()
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func detach() {
        controller.view.removeFromSuperview()
    }
}
