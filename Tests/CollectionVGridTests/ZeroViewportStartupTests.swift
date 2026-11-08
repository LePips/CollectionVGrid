#if os(iOS)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ZeroViewportStartupTests {
    @Test
    func `insets consuming the viewport do not realize collapsed cells`() async throws {
        let layout = CollectionVGridLayout.columns(2, insets: .init(top: 10, leading: 100, bottom: 10, trailing: 100))
        let data = Array(0 ..< 100)
        var configurations = 0
        let grid = UICollectionVGrid(
            id: \Int.self, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil
        ) { _, location in
            if location.column >= 0 {
                configurations += 1
            }
            return Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        grid.frame = window.bounds
        controller.view.addSubview(grid)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(data: data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        grid.layoutIfNeeded()
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never
        collection.layoutIfNeeded()
        let initialConfigurations = configurations

        grid.frame.size.width = 100
        grid.setNeedsLayout()
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        grid.update(data: Array(0 ..< 200), layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        collection.layoutIfNeeded()
        #expect(collection.numberOfItems(inSection: 0) == 200)
        #expect(collection.visibleCells.isEmpty)
        #expect(configurations == initialConfigurations)

        grid.frame.size.width = 800
        grid.setNeedsLayout()
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        collection.layoutIfNeeded()
        #expect(!collection.visibleCells.isEmpty)
        #expect(collection.visibleCells.count < 10)
        #expect(configurations < initialConfigurations + 10)
    }

    @Test
    func `attaching before the first size never materializes the whole data set`() async throws {
        let layout = CollectionVGridLayout.columns(2)
        let data = Array(0 ..< 100)
        var configurations = 0
        let grid = UICollectionVGrid(
            id: \Int.self, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil
        ) { _, location in
            if location.column >= 0 {
                configurations += 1
            }
            return VStack(spacing: 7) {
                Color.blue
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Title").frame(height: 24)
            }
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        controller.view.addSubview(grid)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(data: data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never
        #expect(configurations == 0)

        grid.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        grid.setNeedsLayout()
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        collection.layoutIfNeeded()
        #expect(collection.visibleCells.count < 10)
        #expect(configurations < 10)
        let item = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(abs(item.size.width - 385) < 0.001)
        #expect(abs(item.size.height - (385 * 1.5 + 31)) < 0.001)
    }
}
#endif
