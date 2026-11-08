#if canImport(UIKit)
import SwiftUI

let cellReuseIdentifier = "HostingCollectionViewCell"

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    private var hostingController: UIHostingController<CollectionItemContent<Content>>?
    /// The collection's content generation when this cell's view was last supplied.
    private(set) var contentGeneration = 0

    func setup(view: Content, id: AnyHashable? = nil, generation: Int = 0, usesFixedSize: Bool = false, environment: EnvironmentValues? = nil) {
        contentGeneration = generation
        let root = CollectionItemContent(content: view, identity: id, environment: environment)
        if let hostingController {
            hostingController.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
        // The enclosing collection owns viewport and keyboard insets. Nested hosts
        // must use the entire cell: iOS 18 can otherwise classify a partially
        // offscreen cell's bottom safe area as keyboard avoidance and shift it.
        controller.safeAreaRegions = []
        controller.view.backgroundColor = nil
        controller.view.translatesAutoresizingMaskIntoConstraints = usesFixedSize
        if usesFixedSize {
            // Grid layout supplies both dimensions. Lists still need constraints
            // to derive self-sizing row heights from their hosted content.
            controller.view.frame = contentView.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        contentView.addSubview(controller.view)
        if !usesFixedSize {
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
        hostingController = controller
    }
}
#endif
