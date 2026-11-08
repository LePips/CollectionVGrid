#if os(macOS)
import AppKit
@testable import CollectionVGrid
import Testing

@Suite(.serialized)
@MainActor
struct AppKitSubpointLayoutTests {
    @Test(arguments: [false, true])
    func `subpoint groups return every intersecting item`(horizontal: Bool) {
        let source = SubpointDataSource()
        let collection = NSCollectionView()
        let layout = CollectionLayout()
        collection.collectionViewLayout = layout
        collection.dataSource = source
        collection.reloadData()
        layout.horizontal = horizontal
        layout.lanes = 2
        layout.itemSize = CGSize(width: 0.125, height: 0.125)
        layout.itemSpacing = 0.125
        layout.lineSpacing = 0.125
        layout.prepare()
        #expect(layout.count == 10000)

        let rect = horizontal
            ? CGRect(x: 100.0625, y: 0, width: 0.75, height: 1)
            : CGRect(x: 0, y: 100.0625, width: 1, height: 0.75)
        let expected = (0 ..< layout.count).compactMap { index -> IndexPath? in
            let path = IndexPath(item: index, section: 0)
            return layout.layoutAttributesForItem(at: path)?.frame.intersects(rect) == true ? path : nil
        }
        let actual = layout.layoutAttributesForElements(in: rect).map(\.indexPath)
        #expect(actual == expected)
        #expect(actual.count == 8)
    }

    @Test(arguments: [CGFloat.zero, .leastNonzeroMagnitude])
    func `degenerate stride and overflowing query indices stay bounded`(dimension: CGFloat) {
        let source = SubpointDataSource()
        let collection = NSCollectionView()
        let layout = CollectionLayout()
        collection.collectionViewLayout = layout
        collection.dataSource = source
        collection.reloadData()
        layout.itemSize = CGSize(width: dimension, height: dimension)
        layout.prepare()
        let result = layout.layoutAttributesForElements(in: CGRect(x: 100, y: 100, width: 20, height: 20))
        #expect(result.isEmpty)
    }
}

@MainActor
private final class SubpointDataSource: NSObject, NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        10000
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        NSCollectionViewItem()
    }
}
#endif
