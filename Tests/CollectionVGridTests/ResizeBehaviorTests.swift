@testable import CollectionVGrid
import SwiftUI
import Testing

#if canImport(UIKit)
@Suite(.serialized)
@MainActor
struct ResizeBehaviorTests {

    // MARK: scroll anchoring

    @Test(arguments: [false, true], [CollectionVGridLayout.ItemSizing.aspectRatio, .height])
    func `resizing keeps the item at the top of the visible area`(adaptiveColumns: Bool, sizing: CollectionVGridLayout.ItemSizing) throws {
        let layout: CollectionVGridLayout = adaptiveColumns ? .minWidth(150, itemSizing: sizing) : .columns(4, itemSizing: sizing)
        let (grid, collection, window) = makeGrid(layout: layout, header: false)
        defer { window.isHidden = true }

        func layOut(width: CGFloat) {
            grid.frame.size.width = width
            grid.layoutIfNeeded()
            collection.layoutIfNeeded()
        }

        layOut(width: 1000)
        // Begin a third of the way into item 120's row.
        let start = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 120, section: 0)))
        collection.contentOffset.y = start.frame.minY + start.frame.height / 3
        collection.layoutIfNeeded()
        let originalOffset = collection.contentOffset.y
        let first = try #require(firstVisibleItem(in: collection))

        let pixel = 1 / max(collection.traitCollection.displayScale, 1)
        let widths = Array(stride(from: CGFloat(999.5), through: 420, by: -13.7)) + Array(stride(
            from: CGFloat(420),
            through: 1000,
            by: 17.3
        )) + [1000]
        for width in widths {
            layOut(width: width)
            let attributes = try #require(collection.layoutAttributesForItem(at: IndexPath(item: first.index, section: 0)))
            let expected = attributes.frame.minY + attributes.frame.height * first.fraction
            #expect(abs(collection.contentOffset.y - expected) <= pixel, "Item \(first.index) stays at the top at width \(width)")
        }
        #expect(abs(collection.contentOffset.y - originalOffset) < 0.001, "The sweep returns to the original offset without drift")

        // The top and bottom edges stay pinned.
        collection.contentOffset.y = 0
        layOut(width: 700)
        #expect(collection.contentOffset.y == 0)
        collection.contentOffset.y = collection.contentSize.height - collection.bounds.height
        collection.layoutIfNeeded()
        layOut(width: 900)
        let bottom = collection.contentSize.height - collection.bounds.height
        #expect(abs(collection.contentOffset.y - bottom) <= pixel, "The bottom edge stays pinned")
    }

    @Test
    func `a header keeps its scrolled position while resizing`() throws {
        let (grid, collection, window) = makeGrid(layout: .minWidth(150), header: true)
        defer { window.isHidden = true }
        grid.frame.size.width = 1000
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        let item = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 60, section: 0)))
        collection.contentOffset.y = item.frame.minY
        collection.layoutIfNeeded()

        for width: CGFloat in [860, 640, 1000] {
            grid.frame.size.width = width
            grid.layoutIfNeeded()
            collection.layoutIfNeeded()
            let attributes = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 60, section: 0)))
            #expect(abs(attributes.frame.minY - collection.contentOffset.y) <= 0.5)
        }
    }

    // MARK: insets

    @Test
    func `only width changing insets remeasure content`() throws {
        func layout(top: CGFloat, leading: CGFloat) -> CollectionVGridLayout {
            .columns(3, insets: .init(top: top, leading: leading, bottom: 10, trailing: 10))
        }
        var measurementCount = 0
        let (grid, collection, window) = makeGrid(layout: layout(top: 10, leading: 10), header: false) { location in
            // Measurement hosts the content outside the grid, at no location.
            if location.column < 0 {
                measurementCount += 1
            }
        }
        defer { window.isHidden = true }
        grid.frame.size.width = 800
        grid.layoutIfNeeded()
        collection.layoutIfNeeded()
        let measurements = measurementCount

        for top: CGFloat in [80, 60, 40, 20, 40] {
            grid.update(
                data: Array(0 ..< 300),
                layout: layout(top: top, leading: 10),
                isScrollEnabled: true,
                verticalScrollIndicatorVisibility: .automatic
            )
            grid.layoutIfNeeded()
            collection.layoutIfNeeded()
            let first = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            #expect(first.frame.minY == top, "Top insets still move the content")
        }
        #expect(measurementCount == measurements, "The item width is unchanged, so its measurement still applies")

        grid.update(
            data: Array(0 ..< 300),
            layout: layout(top: 40, leading: 60),
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic
        )
        grid.layoutIfNeeded()
        #expect(measurementCount == measurements + 1, "A new item width is measured again")

        // New data still remeasures when it arrives with a top inset change.
        grid.update(
            data: Array(1 ..< 300),
            layout: layout(top: 70, leading: 60),
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic
        )
        grid.layoutIfNeeded()
        #expect(measurementCount == measurements + 2)
    }

    // MARK: content refresh

    @Test
    func `content updates during a resize reach visible cells once the width settles`() async throws {
        let state = RefreshState()
        let host = UIHostingController(rootView: RefreshFixture(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let collection = try #require(host.view.firstSubview(of: UICollectionView.self))
        let visible = { collection.indexPathsForVisibleItems.map(\.item) }

        // Without a resize, new content reaches every visible cell in the same pass.
        state.label = "B"
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(visible().allSatisfy { state.provided[$0]?.label == "B" })

        // Retained cells are only laid out at their new size until the width settles,
        // after which they also receive their locations in the new column count.
        state.label = "C"
        state.padding = 300
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(visible().contains { state.provided[$0]?.label == "B" }, "Retained cells keep their content while resizing")
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutIfNeeded()
        collection.layoutIfNeeded()
        let columns = RefreshFixture.layout.itemWidth(for: collection.bounds.width).columns
        #expect(visible().allSatisfy { state.provided[$0]?.label == "C" })
        #expect(visible().allSatisfy { item in
            state.provided[item].map { $0.column == item % columns && $0.row == item / columns } ?? false
        })
    }

    // MARK: helpers

    private func makeGrid(
        layout: CollectionVGridLayout,
        header: Bool,
        onContent: @escaping (CollectionVGridLocation) -> Void = { _ in }
    ) -> (UICollectionVGrid<Int, [Int], Int, some View>, UICollectionView, UIWindow) {
        var configuration = CollectionVGrid(uniqueElements: Array(0 ..< 300), id: \.self, layout: layout) { _ in
            VStack(spacing: 4) {
                Color.blue.aspectRatio(2 / 3, contentMode: .fit)
                Text("Title").font(.caption)
            }
        }
        if header {
            configuration = configuration.header { Text("Header").font(.largeTitle).frame(height: 120) }
        }
        let viewProvider = configuration.viewProvider
        let grid = UICollectionVGrid(
            id: \.self, data: configuration.data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil,
            viewProvider: { element, location in
                onContent(location)
                return viewProvider(element, location)
            }
        )
        grid.configure(configuration.contentInsetAdjustmentBehavior(.never))
        grid.update(data: configuration.data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = controller
        controller.view.addSubview(grid)
        grid.frame = window.bounds
        window.makeKeyAndVisible()
        let collection = grid.subviews.compactMap { $0 as? UICollectionView }.first!
        return (grid, collection, window)
    }

    private func firstVisibleItem(in collection: UICollectionView) -> (index: Int, fraction: CGFloat)? {
        let top = collection.contentOffset.y + collection.adjustedContentInset.top
        let first = collection.collectionViewLayout
            .layoutAttributesForElements(in: CGRect(x: 0, y: top, width: collection.bounds.width, height: collection.bounds.height))?
            .filter { $0.representedElementCategory == .cell && $0.frame.maxY > top }
            .min { ($0.frame.minY, $0.indexPath.item) < ($1.frame.minY, $1.indexPath.item) }
        return first.map { ($0.indexPath.item, (top - $0.frame.minY) / $0.frame.height) }
    }
}

@MainActor
@Observable
private final class RefreshState {
    var label = "A"
    var padding: CGFloat = 0
    @ObservationIgnored
    var provided: [Int: (label: String, column: Int, row: Int)] = [:]
}

private struct RefreshFixture: View {
    static let layout = CollectionVGridLayout.minWidth(
        150,
        insets: .init(top: 10, leading: 10, bottom: 10, trailing: 10),
        itemSizing: .height
    )

    let state: RefreshState

    private func card(_ index: Int, location: CollectionVGridLocation, label: String) -> some View {
        if location.column >= 0 {
            state.provided[index] = (label, location.column, location.row)
        }
        return Text("\(label) \(index)").frame(height: 80)
    }

    var body: some View {
        let label = state.label
        CollectionVGrid(uniqueElements: Array(0 ..< 300), id: \.self, layout: Self.layout) { index, location in
            card(index, location: location, label: label)
        }
        .contentInsetAdjustmentBehavior(.never)
        .padding(.leading, state.padding)
        .ignoresSafeArea()
    }
}
#endif

#if os(macOS)
import AppKit

@Suite(.serialized)
@MainActor
struct AppKitResizeBehaviorTests {
    @Test
    func `resizing keeps the item at the top of the viewport`() throws {
        _ = NSApplication.shared
        let configuration = CollectionVGrid(uniqueElements: Array(0 ..< 400), id: \.self, layout: .minWidth(120)) { _ in
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }
        let view = NSCollectionVGrid(configuration: configuration)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        defer {
            view.disconnect()
            window.close()
        }
        view.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        view.layoutSubtreeIfNeeded()

        // The grid preserves the leading item of the row at the top of the viewport.
        let anchor = 140 - 140 % view.collectionLayout.lanes
        let start = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: anchor, section: 0)))
        view.scrollView.contentView.scroll(to: CGPoint(x: 0, y: start.frame.minY))
        view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
        let originalOffset = view.scrollView.contentView.bounds.minY

        for width: CGFloat in [860, 777, 640, 512, 700, 900] {
            view.frame.size.width = width
            view.layoutSubtreeIfNeeded()
            let attributes = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: anchor, section: 0)))
            #expect(
                abs(attributes.frame.minY - view.scrollView.contentView.bounds.minY) <= 1,
                "Item \(anchor) stays at the top at width \(width)"
            )
        }
        #expect(abs(view.scrollView.contentView.bounds.minY - originalOffset) <= 1)
    }
}
#endif

#if canImport(UIKit)
extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}
#endif
