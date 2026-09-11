#if os(macOS)
import AppKit
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct MacOSCollectionVGridTests {
    @Test
    func measurementsAreCachedAndRedrawRemeasures() {
        let proxy = CollectionVGridProxy()
        let model = SizeModel()
        let configuration = CollectionVGrid(count: 10000, layout: .columns(2, insets: .init(), itemSpacing: 10)) { _ in
            Color.blue.frame(height: model.height)
        }.proxy(proxy)
        let view = NSCollectionVGrid(configuration: configuration)
        #expect(view.computeItemSize(forWidth: 210).itemSize == CGSize(width: 100, height: 50))
        // Cached proportions survive content changes until explicitly redrawn.
        model.height = 75
        #expect(view.computeItemSize(forWidth: 410).itemSize == CGSize(width: 200, height: 100))
        #expect(view.computeItemSize(forWidth: 310).itemSize == CGSize(width: 150, height: 75))
        proxy.redraw()
        #expect(view.computeItemSize(forWidth: 210).itemSize.height == 75)
        view.disconnect()
    }

    @Test
    func nativeGridRemainsVirtualizedAcrossResizesAndDistantScroll() async throws {
        _ = NSApplication.shared
        let configuration = CollectionVGrid(
            count: 10000,
            layout: .columns(3, insets: .init(top: 10, leading: 20, bottom: 10, trailing: 20))
        ) { _ in
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }
        let view = NSCollectionVGrid(configuration: configuration)
        let window = makeWindow(view)
        defer { view.disconnect()
            window.close()
        }
        for width: CGFloat in [320, 768, 1366, 414, 1024] {
            window.setContentSize(CGSize(width: width, height: 600))
            view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            view.layoutSubtreeIfNeeded()
            let item = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let expected = (view.scrollView.contentSize.width - 60) / 3
            #expect(abs(item.size.width - expected) < 0.01)
            #expect(abs(item.size.height - expected * 1.5) < 0.1)
            #expect(view.collectionView.numberOfItems(inSection: 0) == 10000)
            #expect(!view.collectionView.visibleItems().isEmpty)
            #expect(view.collectionView.visibleItems().count < 40)
        }
        let distant = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 9000, section: 0)))
        view.scrollView.contentView.scroll(to: distant.frame.origin)
        view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.collectionView.indexPathsForVisibleItems().contains { $0.item >= 9000 })
        #expect(view.collectionView.visibleItems().count < 40)
    }

    @Test
    func minimumWidthsAndLocationsAdaptWhileResizing() async throws {
        _ = NSApplication.shared
        var locations: [Int: CollectionVGridLocation] = [:]
        let configuration = CollectionVGrid(
            uniqueElements: Array(0 ..< 100),
            id: \.self,
            layout: .minWidth(100, insets: .init(), itemSpacing: 10)
        ) { element, location in
            locations[element] = location
            return Color.blue.frame(height: 50)
        }
        let view = NSCollectionVGrid(configuration: configuration)
        #expect(view.computeItemSize(forWidth: 210).columns == 2)
        #expect(view.computeItemSize(forWidth: 410).columns == 3)
        let window = makeWindow(view)
        defer { view.disconnect()
            window.close()
        }
        view.frame = CGRect(x: 0, y: 0, width: 410, height: 400)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(locations[4]?.column == 1)
        #expect(locations[4]?.row == 1)
        view.frame.size.width = 210
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(locations[4]?.column == 0)
        #expect(locations[4]?.row == 2)
    }

    @Test
    func collidingIdentitiesSlicesAndUpdatesAreSafe() {
        let data = (0 ..< 10).map(CollidingID.init)
        func configuration(_ values: ArraySlice<CollidingID>) -> CollectionVGrid<CollidingID, ArraySlice<CollidingID>, CollidingID, Text> {
            CollectionVGrid(uniqueElements: values, id: \.self, layout: .columns(2)) { Text("\($0.value)") }
        }
        let view = NSCollectionVGrid(configuration: configuration(data[3 ..< 7]))
        #expect(view.collectionView.numberOfItems(inSection: 0) == 4)
        let next = [CollidingID(value: 6), CollidingID(value: 4), CollidingID(value: 9)]
        view.update(
            configuration: configuration(next[...]),
            isScrollEnabled: true,
            indicatorVisibility: .automatic,
            dynamicTypeSize: .large
        )
        #expect(view.collectionView.numberOfItems(inSection: 0) == 3)
        view.update(configuration: configuration([]), isScrollEnabled: true, indicatorVisibility: .automatic, dynamicTypeSize: .large)
        #expect(view.collectionView.numberOfItems(inSection: 0) == 0)
        #expect(view.computeItemSize(forWidth: 300).itemSize.height == 0)
        view.scrollToTop(animated: false)
        view.disconnect()
    }

    @Test
    func edgeCallbacksAndProxyReflectCurrentConfiguration() async throws {
        _ = NSApplication.shared
        let proxy = CollectionVGridProxy()
        var top = 0
        var bottom = 0
        let configuration = CollectionVGrid(count: 100, layout: .columns(2)) { _ in Color.blue.frame(height: 50) }
            .proxy(proxy).onReachedTopEdge { top += 1 }.onReachedBottomEdge(offset: .rows(1)) { bottom += 1 }
        let view = NSCollectionVGrid(configuration: configuration)
        let window = makeWindow(view)
        defer { view.disconnect()
            window.close()
        }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(top == 1)
        let last = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 99, section: 0)))
        view.scrollView.contentView.scroll(to: CGPoint(x: 0, y: last.frame.minY))
        view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(bottom == 1)
        proxy.scrollToTop(animated: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(top == 2)
        #expect(view.scrollView.contentView.bounds.minY == 0)
        view.update(configuration: configuration, isScrollEnabled: false, indicatorVisibility: .hidden, dynamicTypeSize: .large)
        #expect(!view.scrollView.allowsScrolling)
        #expect(!view.scrollView.hasVerticalScroller)
    }

    @Test
    func swiftUIRepresentableBuildsAndHosts() async throws {
        _ = NSApplication.shared
        let host = NSHostingController(rootView: CollectionVGrid(count: 100, layout: .columns(2)) { Text("Item \($0)").frame(height: 50) })
        let window = makeWindow(host.view)
        window.contentViewController = host
        defer { window.close() }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let collection = try #require(findCollection(host.view))
        #expect(collection.numberOfItems(inSection: 0) == 100)
    }

    @Test
    func invalidInputsRemainFiniteAndHostingViewsAreReused() {
        for layout: CollectionVGridLayout in [.columns(0), .minWidth(.nan), .minWidth(-20)] {
            let view = NSCollectionVGrid(configuration: CollectionVGrid(count: 1, layout: layout) { _ in Color.blue.frame(height: 50) })
            let size = view.computeItemSize(forWidth: 300)
            #expect(size.columns >= 1)
            #expect(size.itemSize.width.isFinite && size.itemSize.height.isFinite)
            #expect(view.computeItemSize(forWidth: 0).itemSize == .zero)
            view.disconnect()
        }
        let item = HostingCollectionViewItem()
        item.configure(Text("First"), id: 1)
        let host = item.view.subviews.first
        item.prepareForReuse()
        item.configure(Text("Second"), id: 2)
        #expect(item.view.subviews.count == 1)
        #expect(item.view.subviews.first === host)
    }

    @Test
    func visibleLayoutBenchmark() {
        var expectedAttributes: Int?
        for count in [100, 10000, 100_000] {
            let view = NSCollectionVGrid(configuration: CollectionVGrid(count: count, layout: .columns(3)) { _ in
                Color.blue.frame(height: 40)
            })
            view.frame = CGRect(x: 0, y: 0, width: 500, height: 200)
            view.layoutSubtreeIfNeeded()
            var attributes = 0
            let elapsed = ContinuousClock().measure {
                for _ in 0 ..< 5000 {
                    attributes += view.collectionLayout.layoutAttributesForElements(in: CGRect(x: 0, y: 0, width: 500, height: 200)).count
                }
            }
            if let expectedAttributes {
                #expect(attributes == expectedAttributes)
            } else {
                expectedAttributes = attributes
            }
            #expect(attributes > 0 && attributes < 100_000)
            print("LAYOUT_BENCHMARK items=\(count) queries=5000 duration=\(elapsed)")
            view.disconnect()
        }
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        if let view = view as? NSCollectionView {
            return view
        }
        return view.subviews.lazy.compactMap(findCollection).first
    }
}

private final class SizeModel { var height: CGFloat = 50 }
private struct CollidingID: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

#endif
