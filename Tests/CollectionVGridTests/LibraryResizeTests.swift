#if os(iOS)
@testable import CollectionVGrid
import SwiftUI
import Testing

/// Replays the resize patterns of an adaptive media library: a container animates its
/// sidebar padding, a geometry reader rebuilds the grid's layout from its size on every
/// frame, and the layout's top inset follows the navigation bar while scrolling.
@Suite(.serialized)
@MainActor
struct LibraryResizeTests {

    @Test
    func `live window resizing keeps per frame work bounded`() {
        let fixture = LibraryFixture()
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)

        let widths = Array(stride(from: CGFloat(1180), through: 700, by: -6)) + Array(stride(from: CGFloat(700), through: 1180, by: 6))
        let report = fixture.recordLiveResize(widths: widths)

        #expect(report.maximumAnchorDrift < 1, "The scrolled position keeps its leading item at the top")
        #expect(report.measurements == 0, "Resizing reuses the measured proportion")
        #expect(
            report.cellConfigurations * 5 < report.frames * fixture.visibleCellCount,
            "Resizing configures cells entering the viewport, not every visible cell each frame"
        )
    }

    /// System sidebars on iPadOS propose the destination width once and snap the
    /// content to it, so the whole grid resizes within a single frame.
    @Test
    func `sidebar snaps resize the grid within one frame`() async throws {
        let fixture = LibraryFixture()
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(300))

        let report = try await fixture.recordSnaps(widths: [860, 1180, 860, 1180, 860, 1180, 860, 1180])

        #expect(report.maximumAnchorDrift < 1)
        #expect(fixture.visibleLocationsAreCurrent(), "Retained cells receive their location after the column count changes")
    }

    @Test
    func `animated sidebar padding keeps the scrolled position`() async throws {
        let fixture = LibraryFixture()
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(300))

        for padding: CGFloat in [320, 0, 320, 0] {
            let report = try await fixture.recordAnimation {
                fixture.state.padding = padding
            }
            #expect(report.maximumAnchorDrift < 1)
            #expect(report.measurements == 0)
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.visibleLocationsAreCurrent())
    }

    /// A collapsing navigation bar changes only the top inset, at a constant width.
    @Test
    func `navigation bar inset changes do not remeasure or move content`() {
        let fixture = LibraryFixture()
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        let offset = fixture.collection.contentOffset.y

        let insets = Array(stride(from: CGFloat(100), through: 50, by: -2)) + Array(stride(from: CGFloat(50), through: 100, by: 2))
        let report = fixture.recordFrames(values: insets) { fixture.state.topInset = $0 }

        #expect(fixture.collection.contentOffset.y == offset, "Inset changes keep the content offset, as before")
        #expect(report.measurements == 0, "The item width is unchanged, so its measurement still applies")
    }
}

// MARK: - Fixture

@MainActor
@Observable
final class LibraryFixtureState {
    var padding: CGFloat = 0
    var topInset: CGFloat = 100
    @ObservationIgnored
    var locations: [Int: CollectionVGridLocation] = [:]
    /// Content requested to measure an item, which happens outside the grid.
    @ObservationIgnored
    var measurements = 0
    /// Content requested for a cell.
    @ObservationIgnored
    var cellConfigurations = 0
}

@MainActor
final class LibraryFixture {
    let state = LibraryFixtureState()
    let host: UIHostingController<AnyView>
    let window: UIWindow
    private var samples: [CGFloat] = []
    private var anchorItem = 0
    private var anchorDistance: CGFloat = 0

    init() {
        host = UIHostingController(rootView: AnyView(LibraryFixtureRoot(state: state)))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    deinit {
        MainActor.assumeIsolated { window.isHidden = true }
    }

    var collection: UICollectionView {
        host.view.firstSubview(of: UICollectionView.self)!
    }

    var visibleCellCount: Int {
        collection.visibleCells.count
    }

    func layOut(width: CGFloat) {
        window.frame.size.width = width
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func scroll(toItem item: Int) {
        let collection = collection
        collection.layoutIfNeeded()
        let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: item, section: 0))!
        // Leading a row at the top of the viewport, the item is what the grid preserves.
        collection.setContentOffset(CGPoint(x: 0, y: attributes.frame.minY), animated: false)
        collection.layoutIfNeeded()
        anchorItem = item
        anchorDistance = 0
    }

    /// Distance the anchored item moved relative to the top of the viewport.
    func sample() {
        let collection = collection
        collection.layoutIfNeeded()
        guard let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: anchorItem, section: 0))
        else { return }

        samples.append(abs(attributes.frame.minY - collection.contentOffset.y - anchorDistance))
    }

    func visibleLocationsAreCurrent() -> Bool {
        let collection = collection
        collection.layoutIfNeeded()
        guard let first = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else { return false }

        // Count the items sharing the first row to find the current column count.
        let columns = (0 ..< collection.numberOfItems(inSection: 0))
            .prefix {
                collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame.minY == first.frame.minY
            }
            .count
        return collection.indexPathsForVisibleItems.allSatisfy { path in
            guard let location = state.locations[path.item] else { return false }

            return location.column == path.item % columns && location.row == path.item / columns
        }
    }

    private func record(frames: Int = 0, _ body: () async throws -> Void) async rethrows -> GridResizeReport {
        samples = []
        let measurements = state.measurements
        let cellConfigurations = state.cellConfigurations
        try await body()
        return GridResizeReport(
            drift: samples,
            frames: frames,
            measurements: state.measurements - measurements,
            cellConfigurations: state.cellConfigurations - cellConfigurations
        )
    }

    /// Each width is one frame of a live window resize, laid out and committed synchronously.
    func recordLiveResize(widths: [CGFloat]) -> GridResizeReport {
        recordFrames(values: widths) { layOut(width: $0) }
    }

    func recordFrames(values: [CGFloat], apply: (CGFloat) -> Void) -> GridResizeReport {
        samples = []
        let measurements = state.measurements
        let cellConfigurations = state.cellConfigurations
        for value in values {
            apply(value)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            CATransaction.flush()
            sample()
        }
        return GridResizeReport(
            drift: samples,
            frames: values.count,
            measurements: state.measurements - measurements,
            cellConfigurations: state.cellConfigurations - cellConfigurations
        )
    }

    /// Samples each snap frame, then lets it settle before the next.
    func recordSnaps(widths: [CGFloat]) async throws -> GridResizeReport {
        try await record(frames: widths.count) {
            for width in widths {
                layOut(width: width)
                CATransaction.flush()
                sample()
                try await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func recordAnimation(change: () -> Void) async throws -> GridResizeReport {
        try await record {
            change()
            for _ in 0 ..< 40 {
                try await Task.sleep(for: .milliseconds(12))
                sample()
            }
        }
    }
}

struct GridResizeReport {
    let drift: [CGFloat]
    let frames: Int
    let measurements: Int
    let cellConfigurations: Int

    var maximumAnchorDrift: CGFloat {
        drift.max() ?? 0
    }
}

// MARK: - Views

private struct LibraryItem: Identifiable {
    let id: Int
}

/// Mirrors a paging library: animated horizontal padding outside, and a geometry
/// reader that supplies the grid's layout and insets from its current size.
private struct LibraryFixtureRoot: View {
    let state: LibraryFixtureState
    private let items = (0 ..< 600).map(LibraryItem.init)

    var body: some View {
        GeometryReader { outer in
            GeometryReader { geometry in
                let compact = geometry.size.width < 600
                CollectionVGrid(
                    uniqueElements: items,
                    layout: .minWidth(
                        compact ? 160 : 200,
                        insets: EdgeInsets(top: state.topInset, leading: 10, bottom: 34, trailing: 10),
                        itemSpacing: 10,
                        lineSpacing: 10
                    )
                ) { item, location in
                    // Like an adaptive library, content depends on the current size,
                    // so the parent updates the grid on every resize frame.
                    card(item, location: location, width: geometry.size.width)
                }
                .contentInsetAdjustmentBehavior(.never)
            }
            .padding(.leading, state.padding)
            .frame(width: outer.size.width, height: outer.size.height)
            .animation(.smooth(duration: 0.35), value: state.padding)
        }
        .ignoresSafeArea()
    }

    private func card(_ item: LibraryItem, location: CollectionVGridLocation, width: CGFloat) -> LibraryCard {
        if location.column >= 0 {
            state.locations[item.id] = location
            state.cellConfigurations += 1
        } else {
            state.measurements += 1
        }
        return LibraryCard(index: item.id) { _ = (location, width) }
    }
}

/// Shaped like a media poster button: artwork with overlays, a matched transition
/// source, hover and context menu effects, geometry tracking, and an action closure,
/// which makes every re-render evaluate the card's body.
private struct LibraryCard: View {
    @Namespace
    private var namespace
    @State
    private var size: CGSize = .zero

    let index: Int
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill").padding(4)
                    }
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.white)
                            .frame(width: max(0, size.width * 0.4), height: 4)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .contentShape(.contextMenuPreview, Rectangle())
                    .matchedTransitionSource(id: "item", in: namespace)
                    .shadow(radius: 2)
                    .hoverEffect(.highlight)
                Text("Title \(index)").font(.footnote).lineLimit(1)
                Text("2024 · Drama").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Play", systemImage: "play.fill") {}
            Button("Mark Played", systemImage: "checkmark") {}
        }
    }
}
#endif
