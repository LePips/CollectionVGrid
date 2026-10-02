#if canImport(UIKit)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct SafeAreaTests {
    @Test
    func insetAdjustmentCanBeDisabledAndRestoredWithAHeader() async throws {
        let configuration = CollectionVGrid(count: 100, layout: .columns(
            3, insets: .init(top: 20, leading: 40, bottom: 20, trailing: 40), itemSizing: .height
        )) { _ in Color.blue.frame(height: 80) }
            .header { Color.red.frame(height: 100) }
        let grid = UICollectionVGrid(
            id: \.self, data: configuration.data, layout: configuration.layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil,
            viewProvider: configuration.viewProvider
        )
        let host = UIViewController()
        let window = makeWindow(controller: host)
        defer { window.isHidden = true }
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 80, left: 40, bottom: 60, right: 40)
        host.view.addSubview(grid)
        grid.frame = host.view.bounds
        grid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        grid.configure(configuration)
        grid.update(
            data: configuration.data, layout: configuration.layout, isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic, viewProvider: configuration.viewProvider
        )
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.contentInsetAdjustmentBehavior == .automatic)
        for behavior in [UIScrollView.ContentInsetAdjustmentBehavior.never, .always, .never, .automatic] {
            grid.configure(configuration.contentInsetAdjustmentBehavior(behavior))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(collection.contentInsetAdjustmentBehavior == behavior)
            if behavior == .never {
                #expect(collection.adjustedContentInset == .zero)
            } else {
                #expect(collection.adjustedContentInset.top >= 80)
            }
            let header = try #require(collection.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
            ))
            let item = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            #expect(header.frame.minY == 0)
            #expect(header.frame.height == 100)
            #expect(item.frame.minY == 120)
            #expect(item.frame.minX == 40)
        }
    }

    @Test
    func cellContentUsesItsFullBoundsAcrossUpdates() async throws {
        let geometry = CellGeometry()
        let cell = HostingCollectionViewCell<CellContent>(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        cell.setup(view: CellContent(geometry: geometry, color: .blue), id: 1)
        let view = try #require(cell.contentView.subviews.first)
        let host = try #require(view.next as? UIHostingController<AnyView>)
        #expect(!host.safeAreaRegions.contains(.container))
        #expect(host.safeAreaRegions.contains(.keyboard))
        let parent = UIViewController()
        let window = makeWindow(controller: parent)
        defer { window.isHidden = true }
        parent.addChild(host)
        parent.view.addSubview(cell)
        host.didMove(toParent: parent)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 30, left: 40, bottom: 30, right: 40)
        for id in [1, 2] {
            cell.setup(view: CellContent(geometry: geometry, color: .red), id: id)
            parent.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(geometry.size == cell.bounds.size)
            #expect(cell.contentView.subviews.first === view)
            #expect(host.view === view)
        }
    }

    private func makeWindow(controller: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }
}

@MainActor
private final class CellGeometry {
    var size: CGSize = .zero
}

private struct CellContent: View {
    let geometry: CellGeometry
    let color: Color

    var body: some View {
        color.onGeometryChange(for: CGSize.self) { $0.size } action: { geometry.size = $0 }
    }
}
#endif
