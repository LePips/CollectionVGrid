#if canImport(UIKit)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct InsetUpdateTests {
    @Test
    func `retained cells receive their new location after a column change`() throws {
        let data = Array(0 ..< 100)
        var locations: [Int: CollectionVGridLocation] = [:]
        let grid = UICollectionVGrid(
            id: \.self, data: data, layout: .columns(3, itemSizing: .height),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { item, location in
            locations[item] = location
            return Color.blue.frame(height: 100)
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = controller
        controller.view.addSubview(grid)
        grid.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(
            data: data, layout: .columns(3, itemSizing: .height),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
        )
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.layoutIfNeeded()
        collection.layoutIfNeeded()
        let path = IndexPath(item: 8, section: 0)
        let retainedCell = try #require(collection.cellForItem(at: path))
        #expect(locations[8]?.row == 2)
        #expect(locations[8]?.column == 2)

        grid.update(
            data: data, layout: .columns(2, itemSizing: .height),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
        )
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        #expect(collection.cellForItem(at: path) === retainedCell)
        #expect(locations[8]?.row == 4)
        #expect(locations[8]?.column == 0)
    }

    @Test
    func `changing bar insets keeps visible cells and scroll position`() throws {
        let data = Array(0 ..< 100)
        func layout(top: CGFloat, trailing: CGFloat) -> CollectionVGridLayout {
            .columns(3, insets: .init(top: top, leading: 16, bottom: 34, trailing: trailing), itemSizing: .height)
        }
        let grid = UICollectionVGrid(
            id: \.self, data: data, layout: layout(top: 10, trailing: 16),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { _, _ in Color.blue.frame(height: 100) }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = controller
        controller.view.addSubview(grid)
        grid.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(
            data: data, layout: layout(top: 10, trailing: 16),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
        )
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.layoutIfNeeded()
        collection.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        collection.layoutIfNeeded()

        let path = IndexPath(item: 15, section: 0)
        let retainedCell = try #require(collection.cellForItem(at: path))
        // Exercise collapsing top chrome and an asymmetric trailing bar, then
        // reverse both changes while the same row remains visible.
        for top: CGFloat in [82, 63, 44, 24, 44, 63, 82] {
            for trailing: CGFloat in [16, 84, 16] {
                grid.update(
                    data: data, layout: layout(top: top, trailing: trailing),
                    isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
                )
                #expect(collection.alpha == 1, "Inset updates must not crossfade a reloaded collection")
                grid.layoutIfNeeded()
                collection.layoutIfNeeded()
                #expect(collection.contentOffset.y == 300)
                #expect(collection.cellForItem(at: path) === retainedCell)
                let lastInRow = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 17, section: 0)))
                #expect(abs(lastInRow.frame.maxX - (collection.bounds.width - trailing)) < 1)
            }
        }
    }
}
#endif
