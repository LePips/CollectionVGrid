import SwiftUI

let cellReuseIdentifier = "HostingCollectionViewCell"

class HostingCollectionViewCell<Content: View>: UICollectionViewCell {

    private var currentHostingController: UIHostingController<Content>?

    override func prepareForReuse() {
        super.prepareForReuse()

        currentHostingController?.view.removeFromSuperview()
        currentHostingController = nil
    }

    func setup(view: Content) {
        let hostingController = UIHostingController(rootView: view)
        setup(hostingController: hostingController)
    }

    func setup(hostingController: UIHostingController<Content>) {

        self.currentHostingController?.view.removeFromSuperview()
        self.currentHostingController = nil

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = nil

        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        currentHostingController = hostingController
    }
}
