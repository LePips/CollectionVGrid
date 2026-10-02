#if canImport(UIKit)
import SwiftUI

let cellReuseIdentifier = "HostingCollectionViewCell"

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    private var hostingController: UIHostingController<AnyView>?

    func setup(view: Content, id: AnyHashable? = nil) {
        let root = AnyView(view.id(id))
        if let hostingController {
            hostingController.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
        // Cell bounds already include the collection's layout and scroll insets.
        controller.safeAreaRegions.remove(.container)
        controller.view.backgroundColor = nil
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        hostingController = controller
    }
}
#endif
