#if canImport(UIKit)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionVGridUpdateTests {
    @Test
    func collidingIDsSlicesAndStagedUpdatesKeepTheCorrectElements() async throws {
        var configured: [Int] = []
        let values = (0 ..< 8).map(CollidingID.init)
        let view = UICollectionVGrid(
            id: \.self, data: values[2 ..< 6], layout: .columns(2),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { element, _ in
            configured.append(element.value)
            return Text("\(element.value)").frame(height: 40)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.update(data: values[2 ..< 6], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        view.layoutIfNeeded()
        let next = [CollidingID(value: 5), CollidingID(value: 3), CollidingID(value: 7)]
        view.update(data: next[...], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        try await Task.sleep(for: .milliseconds(150))
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.numberOfItems(inSection: 0) == 3)
        configured.removeAll()
        view.update(data: next[...], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        #expect(!configured.isEmpty)
        #expect(Set(configured).isSubset(of: Set(next.map(\.value))))

        view.update(data: [], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        #expect(collection.numberOfItems(inSection: 0) == 0)
    }

    @Test
    func hostingControllerSurvivesCellReuse() {
        let cell = HostingCollectionViewCell<Text>()
        cell.setup(view: Text("First"), id: 1)
        let host = cell.contentView.subviews.first
        cell.prepareForReuse()
        cell.setup(view: Text("Second"), id: 2)
        #expect(cell.contentView.subviews.count == 1)
        #expect(cell.contentView.subviews.first === host)
    }
}

private struct CollidingID: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

#endif
