#if canImport(UIKit)
#if canImport(CollectionHStack)
@testable import CollectionHStack
#else
@testable import CollectionVGrid
#endif
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct CollectionDiffUIKitTests {

    @Test
    func `mixed stages publish their counts inside native batches`() throws {
        let initial = CollectionSnapshot(ids: [0, 1, 2, 3])
        let target = CollectionSnapshot(ids: [3, 1, 4])
        let (window, collection, source) = makeCollection(snapshot: initial)
        defer { window.isHidden = true }
        var counts: [Int] = []

        UIView.performWithoutAnimation {
            collection.apply(CollectionDiff(source: initial, target: target)) { snapshot in
                source.snapshot = snapshot
                counts.append(snapshot.count)
            }
            collection.layoutIfNeeded()
        }

        #expect(counts == [2, 3])
        #expect(collection.deletedPaths.flatMap(\.self).map(\.item) == [0, 2])
        #expect(collection.insertedPaths.flatMap(\.self).map(\.item) == [2])
        #expect(collection.moves == [.init(source: 1, target: 0)])
        try verify(collection, matches: target)
    }

    @Test
    func `self index moves and both rotations preserve cell identities`() throws {
        let initial = CollectionSnapshot(ids: Array(0 ..< 7))
        let reversed = CollectionSnapshot(ids: Array((0 ..< 7).reversed()))
        let (window, collection, source) = makeCollection(snapshot: initial)
        defer { window.isHidden = true }

        apply(reversed, to: collection, source: source)

        #expect(collection.moves.contains { $0.source == $0.target })
        try verify(collection, matches: reversed)

        collection.moves = []
        let left = CollectionSnapshot(ids: Array(reversed.ids.dropFirst()) + [reversed.ids[0]])

        apply(left, to: collection, source: source)

        #expect(collection.moves == [.init(source: 0, target: 6)])
        try verify(collection, matches: left)

        collection.moves = []

        apply(reversed, to: collection, source: source)

        #expect(collection.moves == [.init(source: 6, target: 0)])
        try verify(collection, matches: reversed)
    }

    @Test
    func `consecutive carousel edits keep native counts and repetitions`() throws {
        let initial = CollectionSnapshot(ids: [0, 1, 2], count: 100)
        let (window, collection, source) = makeCollection(snapshot: initial)
        defer { window.isHidden = true }
        let targets = [
            CollectionSnapshot(ids: [2, 0, 3, 4], count: 101),
            CollectionSnapshot(ids: [4, 2], count: 101),
            CollectionSnapshot(ids: [Int]()),
            CollectionSnapshot(ids: [8], count: 100),
            CollectionSnapshot(ids: [8], count: 200),
        ]

        for target in targets {
            apply(target, to: collection, source: source)

            try verify(collection, matches: target)
        }
    }

    @Test
    func `detached collection installs the target without batches`() throws {
        let initial = CollectionSnapshot(ids: [0, 1, 2])
        let target = CollectionSnapshot(ids: [2, 3], count: 101)
        let collection = makeView()
        let source = DiffTestDataSource(snapshot: initial)
        collection.dataSource = source
        var counts: [Int] = []

        collection.apply(CollectionDiff(source: initial, target: target)) { snapshot in
            source.snapshot = snapshot
            counts.append(snapshot.count)
        }

        #expect(counts == [101])
        #expect(collection.reloadCount == 1)
        #expect(collection.deletedPaths.isEmpty)
        #expect(collection.insertedPaths.isEmpty)
        #expect(collection.moves.isEmpty)
        #expect(collection.numberOfItems(inSection: 0) == 101)

        let window = mount(collection)
        defer { window.isHidden = true }

        try verify(collection, matches: target)
    }

    @Test
    func `successive animated edits keep the latest target`() async throws {
        let initial = CollectionSnapshot(ids: Array(0 ..< 8))
        let first = CollectionSnapshot(ids: [7, 4, 1, 8])
        let target = CollectionSnapshot(ids: [8, 1, 9, 4, 7])
        let (window, collection, source) = makeCollection(snapshot: initial)
        defer { window.isHidden = true }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                continuation.resume()
            }

            for snapshot in [first, target] {
                collection.apply(CollectionDiff(source: source.snapshot, target: snapshot)) { stage in
                    source.snapshot = stage
                }
            }

            CATransaction.commit()
        }
        collection.layoutIfNeeded()

        try verify(collection, matches: target)
    }

    private func apply(
        _ target: CollectionSnapshot<Int>,
        to collection: DiffTestCollectionView,
        source: DiffTestDataSource
    ) {
        let changes = CollectionDiff(source: source.snapshot, target: target)

        UIView.performWithoutAnimation {
            collection.apply(changes) { snapshot in
                source.snapshot = snapshot
            }
            collection.layoutIfNeeded()
        }
    }

    private func makeCollection(
        snapshot: CollectionSnapshot<Int>
    ) -> (UIWindow, DiffTestCollectionView, DiffTestDataSource) {
        let collection = makeView()
        let source = DiffTestDataSource(snapshot: snapshot)
        collection.dataSource = source
        let window = mount(collection)
        collection.reloadCount = 0
        return (window, collection, source)
    }

    private func makeView() -> DiffTestCollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 30, height: 30)
        let collection = DiffTestCollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 400), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
        return collection
    }

    private func mount(_ collection: UICollectionView) -> UIWindow {
        let window = UIWindow(frame: collection.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(collection)
        window.makeKeyAndVisible()
        collection.layoutIfNeeded()
        return window
    }

    private func verify(_ collection: UICollectionView, matches target: CollectionSnapshot<Int>) throws {
        #expect(collection.numberOfItems(inSection: 0) == target.count)

        if !target.isEmpty {
            #expect(!collection.indexPathsForVisibleItems.isEmpty)
        }

        for path in collection.indexPathsForVisibleItems {
            try #require(target.indices.contains(path.item))
            let item = target[path.item]
            let cell = try #require(collection.cellForItem(at: path))
            #expect(cell.accessibilityIdentifier == "\(item.id)/\(item.repetition)")
        }
    }
}

@MainActor
private final class DiffTestDataSource: NSObject {

    var snapshot: CollectionSnapshot<Int>

    init(snapshot: CollectionSnapshot<Int>) {
        self.snapshot = snapshot
    }
}

extension DiffTestDataSource: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        snapshot.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath)
        let item = snapshot[indexPath.item]
        cell.accessibilityIdentifier = "\(item.id)/\(item.repetition)"
        return cell
    }
}

@MainActor
private final class DiffTestCollectionView: UICollectionView {

    var reloadCount = 0
    var deletedPaths: [[IndexPath]] = []
    var insertedPaths: [[IndexPath]] = []
    var moves: [CollectionDiff<Int>.Move] = []

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }

    override func deleteItems(at indexPaths: [IndexPath]) {
        deletedPaths.append(indexPaths)
        super.deleteItems(at: indexPaths)
    }

    override func insertItems(at indexPaths: [IndexPath]) {
        insertedPaths.append(indexPaths)
        super.insertItems(at: indexPaths)
    }

    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        moves.append(.init(source: indexPath.item, target: newIndexPath.item))
        super.moveItem(at: indexPath, to: newIndexPath)
    }
}
#endif
