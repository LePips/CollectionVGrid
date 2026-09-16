@testable import CollectionVGrid
import SwiftUI
import Testing

private struct StorageValue {
    let id: Int
    let content: String
}

#if canImport(UIKit)
@Suite(.serialized)
@MainActor
struct UIKitSourceBackedContentTests {
    @Test
    func gridRefreshesSameIDsAfterSliceBoundsAndContentChange() throws {
        let original = (0 ..< 8).map { StorageValue(id: $0, content: "old") }
        var seen: [StorageValue] = []
        let view = UICollectionVGrid(
            id: \.id, data: original[2 ..< 5], layout: .columns(2),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { value, _ in
            seen.append(value)
            return Text(value.content).frame(height: 40)
        }
        view.update(data: original[2 ..< 5], layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        let window = present(view)
        defer { window.isHidden = true }
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(!collection.visibleCells.isEmpty)
        let latest = (2 ..< 5).map { StorageValue(id: $0, content: "new") }[...]
        seen.removeAll()
        view.update(data: latest, layout: .columns(2), isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        view.layoutIfNeeded()
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0.content == "new" && (2 ..< 5).contains($0.id) })
        #expect(collection.numberOfItems(inSection: 0) == 3)
    }

    #if os(iOS)
    @Test
    func listRefreshesSameIDsAndHandlesReorderAndRemoval() throws {
        let original = (0 ..< 8).map { StorageValue(id: $0, content: "old") }
        var seen: [StorageValue] = []
        var rows: [Int: Int] = [:]
        let view = UICollectionVList(
            id: \.id, data: original[2 ..< 5], deleteActionProvider: nil, deleteActionTitle: "Delete",
            headerProvider: { Text("Header") }
        ) { value, location in
            seen.append(value)
            rows[location.row] = value.id
            return Text(value.content).frame(height: 40)
        }
        let window = present(view)
        defer { window.isHidden = true }
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.numberOfItems(inSection: 1) == 3)
        let latest = (2 ..< 5).map { StorageValue(id: $0, content: "new") }[...]
        seen.removeAll()
        view.update(data: latest, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        view.layoutIfNeeded()
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0.content == "new" })
        let reordered = Array(latest.reversed())
        rows.removeAll()
        view.update(data: reordered[...], isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        collection.layoutIfNeeded()
        #expect(rows[0] == 4)
        #expect(rows[1] == 3)
        #expect(rows[2] == 2)
        rows.removeAll()
        let inserted = [StorageValue(id: 9, content: "inserted")] + reordered
        view.update(data: inserted[...], isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        collection.layoutIfNeeded()
        #expect(collection.numberOfItems(inSection: 1) == 4)
        #expect(rows[0] == 9)
        view.update(data: [StorageValue]()[...], isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        collection.layoutIfNeeded()
        #expect(collection.numberOfItems(inSection: 1) == 0)
        #expect(collection.numberOfItems(inSection: 0) == 1)
    }
    #endif

    private func present(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        view.subviews.forEach { $0.layoutIfNeeded() }
        return window
    }
}
#endif

#if os(macOS)
import AppKit

@Suite(.serialized)
@MainActor
struct AppKitSourceBackedContentTests {
    @Test
    func snapshotAndVisibleCellsUseLatestSourceAfterSliceBoundsChange() {
        _ = NSApplication.shared
        let original = (0 ..< 8).map { StorageValue(id: $0, content: "old") }
        var seen: [StorageValue] = []
        func configuration(_ values: ArraySlice<StorageValue>) -> CollectionVGrid<StorageValue, ArraySlice<StorageValue>, Int, Text> {
            CollectionVGrid(uniqueElements: values, id: \.id, layout: .columns(2)) { value in
                seen.append(value)
                return Text(value.content)
            }
        }
        let view = NSCollectionVGrid(configuration: configuration(original[2 ..< 5]))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        defer { view.disconnect()
            window.close()
        }
        #expect(!view.collectionView.visibleItems().isEmpty)
        let latest = (2 ..< 5).map { StorageValue(id: $0, content: "new") }[...]
        seen.removeAll()
        view.update(
            configuration: configuration(latest),
            isScrollEnabled: true,
            indicatorVisibility: .automatic,
            dynamicTypeSize: .large
        )
        view.layoutSubtreeIfNeeded()
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0.content == "new" && (2 ..< 5).contains($0.id) })
        let reordered = Array(latest.reversed())
        view.update(
            configuration: configuration(reordered[...]),
            isScrollEnabled: true,
            indicatorVisibility: .automatic,
            dynamicTypeSize: .large
        )
        #expect(view.collectionView.numberOfItems(inSection: 0) == 3)
    }
}
#endif
