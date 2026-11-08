import SwiftUI

/// A concrete hosting root shared by UIKit cells and AppKit items. Updating the
/// same identity preserves SwiftUI state; reusing it for another identity resets it.
struct CollectionItemContent<Content: View>: View {
    let content: Content
    let identity: AnyHashable?

    var environment: EnvironmentValues? = nil

    var body: some View {
        EnvironmentAwareContent(content: content.id(identity), environment: environment)
            .ignoresSafeArea(.container)
    }
}

/// The native adapters choose their scroll-coordinate conventions; the anchor
/// representation and proportional offset semantics are shared.
enum CollectionScrollAnchor {
    case top
    case bottom
    case item(index: Int, offset: CGFloat, isProportional: Bool)
}
