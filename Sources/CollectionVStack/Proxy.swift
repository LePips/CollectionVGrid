import Foundation

public class CollectionVGridProxy: ObservableObject {

    weak var collectionVGrid: _UICollectionVGrid?

    public init() {
        self.collectionVGrid = nil
    }

    /// Forces the `CollectionVGrid` to re-layout its views.
    /// This is useful if the layout is the same, but the views
    /// have changed and require re-drawing.
    public func layout() {
        collectionVGrid?.snapshotReload()
    }

    public func scrollToTop(animated: Bool = true) {
        collectionVGrid?.scrollToTop(animated: animated)
    }
}
