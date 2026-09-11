import Foundation
import SwiftUI

public class CollectionVGridProxy: ObservableObject {

    #if os(macOS)
    weak var collectionVGrid: _NSCollectionVGrid?
    #else
    weak var collectionVGrid: _UICollectionVGrid?
    #endif

    public init() {
        self.collectionVGrid = nil
    }

    /// Remeasures item content and redraws the collection's items.
    ///
    /// Call this after changing content that affects item size. The collection derives
    /// its resize proportions from the new measurement; no sizing values are required.
    @MainActor
    public func redraw() {
        objectWillChange.send()
        collectionVGrid?.snapshotReload()
    }

    @MainActor
    public func scrollToTop(animated: Bool = true) {
        collectionVGrid?.scrollToTop(animated: animated)
    }
}
