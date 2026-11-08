#if os(macOS)
import AppKit
@testable import CollectionVGrid
import SwiftUI
import Testing

/// Native fixture adapter; workloads, content, counters and statistics are shared
/// with UIKit. A real window exercises AppKit tiling and SwiftUI rendering.
@MainActor
final class LibraryFixture {
    let state = LibraryFixtureState()
    let host: NSHostingView<LibraryFixtureRoot>
    let window: NSWindow
    let layoutOnly = ProcessInfo.processInfo.environment["BENCHMARK_APPKIT_LAYOUT_ONLY"] == "1"
    private var anchorItem = 0

    init(itemCount: Int = 600) {
        _ = NSApplication.shared
        _ = NSApp.setActivationPolicy(.accessory)
        host = NSHostingView(rootView: LibraryFixtureRoot(state: state, itemCount: itemCount))
        host.sizingOptions = []
        window = ResizeBenchmarkWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Collection resize benchmark"
        window.contentView = host
        if layoutOnly {
            (window as! ResizeBenchmarkWindow).allowsOffscreenFrame = true
            let rightEdge = NSScreen.screens.map(\.frame.maxX).max() ?? 1728
            window.setFrameOrigin(CGPoint(x: rightEdge + 100, y: 100))
            window.orderBack(nil)
        } else {
            // Keep ordinary app windows from covering the resize fixture while
            // Xcode and the test runner activate. This does not bypass the lock
            // screen; visibility and display callbacks are still required.
            window.level = .floating
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            window.orderFrontRegardless()
        }
        pumpEvents()
    }

    deinit {
        MainActor.assumeIsolated { window.close() }
    }

    var collection: NSCollectionView {
        findCollection(host)!
    }

    var scrollView: NSScrollView {
        collection.enclosingScrollView!
    }

    var visibleCellCount: Int {
        collection.visibleItems().count
    }

    func waitForPresentation() async throws {
        if layoutOnly {
            pumpEvents()
            try #require(
                window.isVisible && !window.occlusionState.contains(.visible),
                "Layout-only measurements require a consistently offscreen window"
            )
            return
        }
        for _ in 0 ..< 50 {
            pumpEvents()
            if window.isVisible, window.occlusionState.contains(.visible) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(window.isVisible && window.occlusionState.contains(.visible), "Benchmark window must be presented on a display")
    }

    private func pumpEvents() {
        for _ in 0 ..< 100 {
            guard let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) else { break }

            NSApp.sendEvent(event)
        }
        NSApp.updateWindows()
    }

    func layOut(width: CGFloat) {
        window.setContentSize(CGSize(width: width, height: 820))
        host.frame.size = CGSize(width: width, height: 820)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    func scroll(toItem item: Int) {
        host.layoutSubtreeIfNeeded()
        let attributes = collection.collectionViewLayout!.layoutAttributesForItem(at: IndexPath(item: item, section: 0))!
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: attributes.frame.minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        host.layoutSubtreeIfNeeded()
        anchorItem = item
    }

    func sample() -> CGFloat {
        host.layoutSubtreeIfNeeded()
        guard let attributes = collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: anchorItem, section: 0))
        else { return 0 }

        return abs(attributes.frame.minY - scrollView.contentView.bounds.minY)
    }

    func visibleLocationsAreCurrent() -> Bool {
        host.layoutSubtreeIfNeeded()
        let columns = (collection.collectionViewLayout as! CollectionLayout).lanes
        return collection.indexPathsForVisibleItems().allSatisfy { path in
            guard let location = state.locations[path.item] else { return false }

            return location.column == path.item % columns && location.row == path.item / columns
        }
    }

    func recordLiveResize(widths: [CGFloat]) -> GridResizeReport {
        recordFrames(values: widths) { layOut(width: $0) }
    }

    func recordFrames(values: [CGFloat], apply: (CGFloat) -> Void) -> GridResizeReport {
        let measurements = state.measurements
        let configurations = state.cellConfigurations
        var drift: [CGFloat] = []
        for width in values {
            apply(width)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            CATransaction.flush()
            drift.append(sample())
        }
        return GridResizeReport(
            drift: drift,
            frames: values.count,
            measurements: state.measurements - measurements,
            cellConfigurations: state.cellConfigurations - configurations
        )
    }

    func recordAnimation(change: () -> Void) async throws -> GridResizeReport {
        let measurements = state.measurements
        let configurations = state.cellConfigurations
        var drift: [CGFloat] = []
        change()
        for _ in 0 ..< 40 {
            try await Task.sleep(for: .milliseconds(12))
            drift.append(sample())
        }
        return GridResizeReport(
            drift: drift,
            frames: 0,
            measurements: state.measurements - measurements,
            cellConfigurations: state.cellConfigurations - configurations
        )
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        if let collection = view as? NSCollectionView {
            return collection
        }
        return view.subviews.lazy.compactMap(findCollection).first
    }
}

private final class ResizeBenchmarkWindow: NSWindow {
    var allowsOffscreenFrame = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsOffscreenFrame ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}
#endif
