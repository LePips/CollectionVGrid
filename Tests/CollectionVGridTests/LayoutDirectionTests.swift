@testable import CollectionVGrid
import SwiftUI
import Testing

@MainActor
struct LayoutDirectionTests {
    @Test
    func `hosted grid mirrors columns and insets`() async throws {
        let proxy = CollectionVGridProxy()
        let layout = CollectionVGridLayout.columns(3, insets: .init(top: 0, leading: 24, bottom: 0, trailing: 8), itemSizing: .height)
        var locations: [Int: CollectionVGridLocation] = [:]
        let grid = CollectionVGrid(uniqueElements: Array(0 ..< 5), id: \.self, layout: layout) { id, location in
            let _ = locations.updateValue(location, forKey: id)
            Color.blue.frame(height: 30)
        }.proxy(proxy)
        func root(_ direction: LayoutDirection) -> some View {
            grid.frame(width: 320, height: 200).environment(\.layoutDirection, direction)
        }

        #if canImport(UIKit)
        let host = UIHostingController(rootView: root(.rightToLeft))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 480, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func frames() throws -> [CGRect] {
            let view = try #require(proxy.collectionVGrid)
            let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
            let viewport = view.convert(view.bounds, to: window)
            return try (0 ..< 5).map {
                let cell = try #require(collection.cellForItem(at: IndexPath(item: $0, section: 0)))
                return cell.convert(cell.bounds, to: window).offsetBy(dx: -viewport.minX, dy: 0)
            }
        }
        #else
        let host = NSHostingController(rootView: root(.rightToLeft))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.close() }
        func frames() throws -> [CGRect] {
            let view = try #require(proxy.collectionVGrid as? NSView)
            let scroll = try #require(view.subviews.compactMap { $0 as? NSScrollView }.first)
            let collection = try #require(scroll.documentView as? NSCollectionView)
            let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            return try (0 ..< 5).map {
                let item = try #require(collection.item(at: IndexPath(item: $0, section: 0)))
                return item.view.convert(item.view.bounds, to: nil).offsetBy(dx: -viewport.minX, dy: 0)
            }
        }
        #endif

        try await Task.sleep(for: .milliseconds(200))
        let rtl = try frames()
        #expect(abs(rtl[0].maxX - 296) <= 1)
        #expect(abs(rtl[2].minX - 8) <= 1)
        #expect(abs(rtl[3].maxX - rtl[0].maxX) <= 1)
        #expect(rtl[4].minX < rtl[3].minX)
        #expect(locations[3]?.column == 0)
        #expect(locations[3]?.row == 1)

        host.rootView = root(.leftToRight)
        try await Task.sleep(for: .milliseconds(200))
        let ltr = try frames()
        #expect(abs(ltr[0].minX - 24) <= 1)
        #expect(abs(ltr[2].maxX - 312) <= 1)
        #expect(ltr[4].minX > ltr[3].minX)
    }
}
