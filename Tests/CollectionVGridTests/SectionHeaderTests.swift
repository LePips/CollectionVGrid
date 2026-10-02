@testable import CollectionVGrid
import Observation
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct SectionHeaderTests {
    @Test
    func parentStateReadOnlyByTheHeaderUpdatesItsLayout() async throws {
        let model = HeaderModel()
        let root = HeaderUpdateFixture(model: model)
        #if canImport(UIKit)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #else
        _ = NSApplication.shared
        let host = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.setContentSize(CGSize(width: 400, height: 600))
        host.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        window.orderBack(nil)
        defer { window.close() }
        #endif
        for height: CGFloat in [80, 140, 50] {
            model.height = height
            try await Task.sleep(for: .milliseconds(100))
            #if canImport(UIKit)
            host.view.layoutIfNeeded()
            func findCollection(_ view: UIView) -> UICollectionView? {
                (view as? UICollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
            }
            let collection = try #require(findCollection(host.view))
            let attributes = collection.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
            )
            #else
            host.view.layoutSubtreeIfNeeded()
            func findCollection(_ view: NSView) -> NSCollectionView? {
                (view as? NSCollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
            }
            let collection = try #require(findCollection(host.view))
            let attributes = collection.collectionViewLayout?.layoutAttributesForSupplementaryView(
                ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
            )
            #endif
            #expect(try #require(attributes).frame.height == height)
        }
    }

    @Test
    func measurementIsCachedAndTheHostSurvivesReuse() throws {
        let counter = HeaderMeasurements()
        let header = CollectionHeader(content: AnyView(HeaderLayout(counter: counter) { Color.blue }))
        #expect(header.size(forWidth: 0) == .zero)
        #expect(header.size(forWidth: 300) == CGSize(width: 300, height: 150))
        let measurements = counter.value
        for _ in 0 ..< 100 {
            #expect(header.size(forWidth: 300).height == 150)
        }
        #expect(counter.value == measurements)
        #expect(header.size(forWidth: 200) == CGSize(width: 200, height: 100))

        let first = HostingCollectionViewHeader(frame: .zero)
        let second = HostingCollectionViewHeader(frame: .zero)
        header.attach(to: first)
        let host = try #require(first.subviews.first)
        header.attach(to: second)
        #expect(first.subviews.isEmpty)
        #expect(second.subviews.first === host)
        header.update(content: AnyView(Color.red.frame(height: 75)))
        #expect(header.size(forWidth: 200) == CGSize(width: 200, height: 75))
        #expect(second.subviews.first === host)
    }

    @Test
    func headerModifierPreservesOtherConfiguration() {
        let proxy = CollectionVGridProxy()
        var reachedTop = false
        let grid = configuration(count: 1)
            .proxy(proxy)
            .onRefresh {}
            .onReachedTopEdge { reachedTop = true }
            .header { Text("Library") }
        #expect(grid.proxy === proxy)
        #expect(grid.refreshAction != nil)
        grid.onReachedTopEdge()
        #expect(reachedTop)
    }

    @Test
    func headerScrollsResizesUpdatesAndDisappearsWithoutChangingItems() async throws {
        let harness = GridHarness(configuration(count: 10000, headerHeight: 80))
        defer { harness.close() }
        try await harness.layout()
        #expect(try harness.headerFrame().height == 80)
        #expect(try harness.itemFrame().minY == 90)
        #expect(harness.itemCount == 10000)
        #expect(harness.visibleItemCount > 0 && harness.visibleItemCount < 100)

        harness.scroll(to: 2000)
        try await harness.layout()
        #expect(try harness.headerFrame().minY == 0, "The header must not pin to the viewport")
        #expect(!harness.headerIsVisible)
        #expect(harness.visibleItemCount > 0 && harness.visibleItemCount < 100)
        harness.scrollToTop()
        try await harness.layout()
        #expect(harness.headerIsVisible)

        harness.apply(configuration(count: 10000, headerHeight: 140))
        try await harness.layout()
        #expect(try harness.headerFrame().height == 140)
        #expect(try harness.itemFrame().minY == 150)

        harness.apply(configuration(count: 10000).header(isVisible: false) {
            Color.red.frame(height: 140)
        })
        try await harness.layout()
        #expect(!harness.headerIsVisible)
        #expect(try harness.itemFrame().minY == 10)
        #expect(harness.itemCount == 10000)

        harness.apply(configuration(count: 10000).header(isVisible: true) {
            Color.red.frame(height: 140)
        })
        try await harness.layout()
        #expect(harness.headerIsVisible)
        #expect(try harness.headerFrame().height == 140)
        #expect(try harness.itemFrame().minY == 150)

        harness.apply(configuration(count: 10000).header {
            Color.blue.aspectRatio(2, contentMode: .fit)
        })
        harness.resize(width: 400)
        try await harness.layout()
        let frame = try harness.headerFrame()
        #expect(abs(frame.height - frame.width / 2) < 1)
        harness.resize(width: 600)
        try await harness.layout()
        let resized = try harness.headerFrame()
        #expect(resized.width > frame.width)
        #expect(abs(resized.height - resized.width / 2) < 1)

        harness.apply(configuration(count: 10000))
        try await harness.layout()
        #expect(!harness.headerIsVisible)
        #expect(try harness.itemFrame().minY == 10)
    }

    @Test
    func emptyGridCanDisplayAddAndRemoveAHeader() async throws {
        let harness = GridHarness(configuration(count: 0).header(isVisible: false) {
            Color.red.frame(height: 80)
        })
        defer { harness.close() }
        try await harness.layout()
        #expect(harness.itemCount == 0)
        #expect(!harness.headerIsVisible)

        harness.apply(configuration(count: 0, headerHeight: 80))
        try await harness.layout()
        #expect(harness.headerIsVisible)
        #expect(try harness.headerFrame().height == 80)
        harness.apply(configuration(count: 0))
        try await harness.layout()
        #expect(!harness.headerIsVisible)
        harness.apply(configuration(count: 0, headerHeight: 120))
        try await harness.layout()
        #expect(harness.headerIsVisible)
        #expect(try harness.headerFrame().height == 120)
    }
}

private typealias Configuration = CollectionVGrid<Int, [Int], Int, AnyView>

@Observable
private final class HeaderModel {
    var height: CGFloat = 80
}

private struct HeaderUpdateFixture: View {
    let model: HeaderModel

    var body: some View {
        CollectionVGrid(count: 100, layout: .columns(2)) { _ in Color.blue.frame(height: 40) }
            .header { Color.red.frame(height: model.height) }
    }
}

@MainActor
private func configuration(count: Int, headerHeight: CGFloat? = nil) -> Configuration {
    let grid = CollectionVGrid(count: count, layout: .columns(
        3, insets: .init(top: 10, leading: 20, bottom: 10, trailing: 20), itemSizing: .height
    )) { _ in AnyView(Color.blue.frame(height: 40)) }
    if let headerHeight {
        return grid.header { Color.red.frame(height: headerHeight) }
    }
    return grid
}

private final class HeaderMeasurements { var value = 0 }

private struct HeaderLayout: Layout {
    let counter: HeaderMeasurements

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        counter.value += 1
        let width = proposal.width ?? 300
        return CGSize(width: width, height: width / 2)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor
private final class GridHarness {
    #if canImport(UIKit)
    let grid: UICollectionVGrid<Int, [Int], Int, AnyView>
    let window: UIWindow
    var nativeLayout: UICollectionViewLayout? {
        collection.collectionViewLayout
    }

    var collection: UICollectionView {
        grid.subviews.compactMap { $0 as? UICollectionView }.first!
    }
    #else
    let grid: NSCollectionVGrid<Int, [Int], Int, AnyView>
    let window: NSWindow
    var nativeLayout: NSCollectionViewLayout? {
        collection.collectionViewLayout
    }

    var collection: NSCollectionView {
        grid.collectionView
    }
    #endif

    init(_ configuration: Configuration) {
        #if canImport(UIKit)
        grid = UICollectionVGrid(
            id: \.self, data: configuration.data, layout: configuration.layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil,
            viewProvider: configuration.viewProvider
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(grid)
        grid.frame = window.bounds
        window.makeKeyAndVisible()
        #else
        _ = NSApplication.shared
        grid = NSCollectionVGrid(configuration: configuration)
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = grid
        window.orderBack(nil)
        #endif
        apply(configuration)
    }

    func apply(_ configuration: Configuration) {
        #if canImport(UIKit)
        grid.configure(configuration)
        grid.update(
            data: configuration.data,
            layout: configuration.layout,
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic,
            viewProvider: configuration.viewProvider
        )
        #else
        grid.update(configuration: configuration, isScrollEnabled: true, indicatorVisibility: .automatic, dynamicTypeSize: .large)
        #endif
    }

    func layout() async throws {
        #if canImport(UIKit)
        grid.setNeedsLayout()
        grid.layoutIfNeeded()
        #else
        grid.needsLayout = true
        grid.layoutSubtreeIfNeeded()
        #endif
        try await Task.sleep(for: .milliseconds(80))
    }

    func headerFrame() throws -> CGRect {
        try #require(nativeLayout?.layoutAttributesForSupplementaryView(
            ofKind: headerKind, at: IndexPath(item: 0, section: 0)
        )).frame
    }

    func itemFrame() throws -> CGRect {
        try #require(nativeLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
    }

    var itemCount: Int {
        collection.numberOfItems(inSection: 0)
    }

    #if canImport(UIKit)
    private var headerKind: String {
        UICollectionView.elementKindSectionHeader
    }

    var visibleItemCount: Int {
        collection.visibleCells.count
    }

    var headerIsVisible: Bool {
        !collection.visibleSupplementaryViews(ofKind: headerKind).isEmpty
    }

    func scroll(to y: CGFloat) {
        collection.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }

    func resize(width: CGFloat) {
        grid.frame.size.width = width
    }

    func close() {
        window.isHidden = true
    }
    #else
    private var headerKind: String {
        NSCollectionView.elementKindSectionHeader
    }

    var visibleItemCount: Int {
        collection.visibleItems().count
    }

    var headerIsVisible: Bool {
        !collection.visibleSupplementaryViews(ofKind: headerKind).isEmpty
    }

    func scroll(to y: CGFloat) {
        grid.scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        grid.scrollView.reflectScrolledClipView(grid.scrollView.contentView)
    }

    func resize(width: CGFloat) {
        window.setContentSize(CGSize(width: width, height: 600))
    }

    func close() {
        grid.disconnect()
        window.close()
    }
    #endif

    func scrollToTop() {
        grid.scrollToTop(animated: false)
    }
}
