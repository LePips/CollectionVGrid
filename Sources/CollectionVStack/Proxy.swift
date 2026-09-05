import Foundation

public class CollectionVGridProxy: ObservableObject {

    weak var collectionVGrid: _UICollectionVGrid?

    public init() {
        self.collectionVGrid = nil
    }

    /// Remeasures item content and redraws the collection's items.
    ///
    /// Call this after changing content that affects item size. The collection derives
    /// its resize proportions from the new measurement; no sizing values are required.
    public func redraw() {
        objectWillChange.send()
        collectionVGrid?.snapshotReload()
    }

    public func scrollToTop(animated: Bool = true) {
        collectionVGrid?.scrollToTop(animated: animated)
    }
}
