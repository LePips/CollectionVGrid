@testable import CollectionVGrid
import SwiftUI
import Testing

/// Artwork scales with width, while captions and their spacing do not. Measuring a
/// ratio for the entire button cannot describe this layout, even without wrapping.
@Suite(.serialized)
@MainActor
struct CompositeCellSizingTests {
    @Test
    func `default sizing measures composite content at each exact width`() {
        let layout = CollectionVGridLayout.columns(2, insets: .init(), itemSpacing: 10)
        let content = {
            VStack(spacing: 7) {
                Color.blue.aspectRatio(2 / 3, contentMode: .fit)
                Text("Poster title").font(.system(size: 16)).frame(height: 24)
            }
        }
        #if canImport(UIKit)
        let grid = UICollectionVGrid(
            id: \Int.self, data: [0], layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil,
            viewProvider: { _, _ in content() }
        )
        #else
        let grid = NSCollectionVGrid(configuration: CollectionVGrid(count: 1, layout: layout) { _ in content() })
        defer { grid.disconnect() }
        #endif

        for width: CGFloat in [410, 409.75, 409.5, 410.25, 310, 610, 410] {
            let size = grid.computeItemSize(forWidth: width).itemSize
            #expect(abs(size.width - (width - 10) / 2) < 0.0001)
            #expect(abs(size.height - (size.width * 1.5 + 31)) < 0.0001)
        }
    }
}

#if os(iOS)
@Suite(.serialized)
@MainActor
struct HostedCompositeCellSizingTests {
    @Test(arguments: [false, true], [ContentMode.fit, .fill])
    func `poster and caption geometry fits every cell during fine resizing`(adaptive: Bool, mode: ContentMode) async throws {
        let layout: CollectionVGridLayout = adaptive
            ? .minWidth(150, insets: .init(), itemSpacing: 10, lineSpacing: 12)
            : .columns(3, insets: .init(), itemSpacing: 10, lineSpacing: 12)
        let host = UIHostingController(rootView: CollectionVGrid(count: 10000, layout: layout) { index in
            Button {} label: {
                VStack(alignment: .leading, spacing: 7) {
                    Rectangle()
                        .fill(.blue)
                        .aspectRatio(2 / 3, contentMode: mode)
                        .background(GeometryMarker(index: index, role: .poster))
                    Text("Poster title")
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .frame(height: 24)
                        .background(GeometryMarker(index: index, role: .caption))
                }
            }.buttonStyle(.borderless)
        }
        .contentInsetAdjustmentBehavior(.never)
        .ignoresSafeArea())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for width: CGFloat in [800, 799.5, 799, 800.5, 479.5, 480, 480.5, 1000, 510, 800] {
            window.frame.size.width = width
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            host.view.layoutIfNeeded()
            let collection = try #require(host.view.firstSubview(of: UICollectionView.self))
            collection.layoutIfNeeded()
            let item = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            item.layoutIfNeeded()
            let markers = descendants(of: item).compactMap { $0 as? MarkerView }
            let poster = try #require(markers.first { $0.role == .poster })
            let caption = try #require(markers.first { $0.role == .caption })
            let posterFrame = poster.convert(poster.bounds, to: collection)
            let captionFrame = caption.convert(caption.bounds, to: collection)
            let cellFrame = item.convert(item.bounds, to: collection)
            let columns = layout.itemWidth(for: collection.bounds.width).columns
            let nextRow = try #require(collection.layoutAttributesForItem(at: IndexPath(item: columns, section: 0)))
            let tolerance = 1 / max(collection.traitCollection.displayScale, 1)
            #expect(abs(posterFrame.width - cellFrame.width) <= tolerance)
            #expect(abs(posterFrame.height - posterFrame.width * 1.5) <= tolerance)
            #expect(abs(captionFrame.minY - posterFrame.maxY - 7) <= tolerance)
            #expect(captionFrame.maxY <= cellFrame.maxY + tolerance)
            #expect(abs(cellFrame.height - (cellFrame.width * 1.5 + 31)) <= tolerance)
            #expect(nextRow.frame.minY >= captionFrame.maxY + 12 - tolerance)
            #expect(collection.visibleCells.count < 100)
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private enum MarkerRole { case poster, caption }

private final class MarkerView: UIView {
    var role: MarkerRole = .poster
}

private struct GeometryMarker: UIViewRepresentable {
    let index: Int
    let role: MarkerRole

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.role = role
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

@Suite(.serialized)
@MainActor
struct AppKitHostedCompositeCellSizingTests {
    @Test(arguments: [false, true], [ContentMode.fit, .fill])
    func `native poster geometry stays inside its row during fine resizing`(adaptive: Bool, mode: ContentMode) async throws {
        _ = NSApplication.shared
        let layout: CollectionVGridLayout = adaptive
            ? .minWidth(150, insets: .init(), itemSpacing: 10, lineSpacing: 12)
            : .columns(3, insets: .init(), itemSpacing: 10, lineSpacing: 12)
        let configuration = CollectionVGrid(count: 10000, layout: layout) { _ in
            Button {} label: {
                VStack(alignment: .leading, spacing: 7) {
                    Rectangle()
                        .fill(.blue)
                        .aspectRatio(2 / 3, contentMode: mode)
                        .background(AppKitGeometryMarker(role: .poster))
                    Text("Poster title")
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .frame(height: 24)
                        .background(AppKitGeometryMarker(role: .caption))
                }
            }.buttonStyle(.borderless)
        }
        let view = NSCollectionVGrid(configuration: configuration)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        defer {
            view.disconnect()
            window.close()
        }

        for width: CGFloat in [800, 799.5, 799, 800.5, 479.5, 480, 480.5, 1000, 510, 800] {
            window.setContentSize(CGSize(width: width, height: 900))
            view.frame.size.width = width
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            view.layoutSubtreeIfNeeded()
            let item = try #require(view.collectionView.item(at: IndexPath(item: 0, section: 0)))
            item.view.layoutSubtreeIfNeeded()
            let markers = descendants(of: item.view).compactMap { $0 as? AppKitMarkerView }
            let poster = try #require(markers.first { $0.role == .poster })
            let caption = try #require(markers.first { $0.role == .caption })
            let posterFrame = poster.convert(poster.bounds, to: view.collectionView)
            let captionFrame = caption.convert(caption.bounds, to: view.collectionView)
            let cellFrame = item.view.convert(item.view.bounds, to: view.collectionView)
            let nextRow = try #require(view.collectionLayout.layoutAttributesForItem(
                at: IndexPath(item: view.collectionLayout.lanes, section: 0)
            ))
            let tolerance = 1 / window.backingScaleFactor
            #expect(abs(posterFrame.width - cellFrame.width) <= tolerance)
            #expect(abs(posterFrame.height - posterFrame.width * 1.5) <= tolerance)
            #expect(abs(captionFrame.minY - posterFrame.maxY - 7) <= tolerance)
            #expect(captionFrame.maxY <= cellFrame.maxY + tolerance)
            #expect(abs(cellFrame.height - (cellFrame.width * 1.5 + 31)) <= tolerance)
            #expect(nextRow.frame.minY >= captionFrame.maxY + 12 - tolerance)
            #expect(view.collectionView.visibleItems().count < 100)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private enum AppKitMarkerRole { case poster, caption }

private final class AppKitMarkerView: NSView {
    var role: AppKitMarkerRole = .poster
}

private struct AppKitGeometryMarker: NSViewRepresentable {
    let role: AppKitMarkerRole

    func makeNSView(context: Context) -> AppKitMarkerView {
        let view = AppKitMarkerView()
        view.role = role
        return view
    }

    func updateNSView(_ nsView: AppKitMarkerView, context: Context) {}
}
#endif
