#if canImport(UIKit)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionVGridUpdateTests {

    @Test
    func `colliding I ds slices and staged updates keep the correct elements`() async throws {
        var configured: [Int] = []
        let values = (0 ..< 8).map(CollidingID.init)
        let view = UICollectionVGrid(
            id: \.self,
            data: values[2 ..< 6],
            layout: .columns(2),
            onReachedBottomEdge: {},
            onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {},
            onReachedTopEdgeOffset: .offset(0),
            proxy: nil
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

        view.removeFromSuperview()

        view.update(data: next[...], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)

        #expect(collection.numberOfItems(inSection: 0) == next.count)

        controller.view.addSubview(view)
        view.layoutIfNeeded()
        configured.removeAll()

        view.update(data: next[...], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)

        #expect(!configured.isEmpty)
        #expect(Set(configured).isSubset(of: Set(next.map(\.value))))
    }

    @Test
    func `hosting controller survives cell reuse`() {
        let cell = HostingCollectionViewCell<Text>()
        cell.setup(view: Text("First"), id: 1)
        let host = cell.contentView.subviews.first
        cell.prepareForReuse()
        cell.setup(view: Text("Second"), id: 2)
        #expect(cell.contentView.subviews.count == 1)
        #expect(cell.contentView.subviews.first === host)
    }

    @Test
    func `list cells still derive their height from hosted content`() {
        // Use a fixed-height content type while retaining the list's default
        // constraint sizing path, independent of a grid's supplied itemSize.
        let row = HostingCollectionViewCell<AnyView>(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        row.setup(view: AnyView(Color.blue.frame(height: 140)))
        let fitted = row.contentView.systemLayoutSizeFitting(
            CGSize(width: 300, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(abs(fitted.height - 140) < 0.5)
    }

    @Test(arguments: [true, false])
    func `hosted state survives resize and resets for a reused identity`(usesFixedSize: Bool) async throws {
        var seen: [Int] = []
        let cell = HostingCollectionViewCell<StatefulCellContent>()
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        window.rootViewController = controller
        controller.view.addSubview(cell)
        cell.frame = CGRect(x: 0, y: 0, width: 250, height: 300)
        cell.setup(view: StatefulCellContent(seed: 1) { seen.append($0) }, id: 10, usesFixedSize: usesFixedSize)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        func settle() async throws {
            controller.view.layoutIfNeeded()
            cell.layoutIfNeeded()
            cell.contentView.subviews.forEach { $0.layoutIfNeeded() }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await settle()
        #expect(seen.last == 1)
        let host = try #require(cell.contentView.subviews.first)
        cell.setup(view: StatefulCellContent(seed: 99) { seen.append($0) }, id: 10, usesFixedSize: usesFixedSize)
        for width: CGFloat in [180, 310.5, 220, 250] {
            cell.frame.size.width = width
            try await settle()
            #expect(host.frame.origin == cell.contentView.bounds.origin)
            // UIKit rounds both autoresizing and constraints to display pixels.
            let tolerance = 0.5 / max(cell.traitCollection.displayScale, 1)
            #expect(abs(host.frame.width - cell.contentView.bounds.width) <= tolerance)
            #expect(host.frame.height == cell.contentView.bounds.height)
            #expect(seen.last == 1)
        }
        cell.prepareForReuse()
        cell.setup(view: StatefulCellContent(seed: 2) { seen.append($0) }, id: 20, usesFixedSize: usesFixedSize)
        try await settle()
        #expect(seen.last == 2)
        #expect(cell.contentView.subviews.first === host)
    }
}

private struct StatefulCellContent: View {
    @State
    private var value: Int
    let record: (Int) -> Void

    init(seed: Int, record: @escaping (Int) -> Void) {
        _value = State(initialValue: seed)
        self.record = record
    }

    var body: some View {
        record(value)
        return Color.blue
    }
}

private struct CollidingID: Hashable {

    let value: Int
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

#endif
