import SwiftUI

/// Shared measurement lifetime and cache policy. Native layouts supply the final
/// item width (including any platform-specific rounding) and representative content.
@MainActor
final class CollectionItemSizing<Content: View> {
    private var cache = ItemSizeCache()
    private var measurer = ContentMeasurer<Content>()

    func invalidate() {
        cache = ItemSizeCache()
        measurer = ContentMeasurer()
    }

    func size(width: CGFloat, sizing: CollectionVGridLayout.ItemSizing, environment: EnvironmentValues? = nil, content: () -> (Content, AnyHashable)) -> CGSize {
        guard width.isFiniteAndPositive else {
            return CGSize(width: nonnegativeFinite(width), height: 0)
        }

        return cache.size(width: width, sizing: sizing) {
            let (content, identity) = content()
            return measurer.size(of: content, identity: identity, width: width, environment: environment)
        }
    }
}
