#if os(iOS)
@testable import CollectionVGrid
import SwiftUI
import Testing

/// Isolates the unchanged identity-comparison path from SwiftUI layout and rendering.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["COLLECTION_RESIZE_BENCHMARK"] == "1"))
@MainActor
struct ResizeDataUpdateBenchmarks {
    @Test(arguments: [600, 10000, 100_000])
    func `native flow layout cost`(itemCount: Int) async throws {
        let fixture = LibraryFixture(itemCount: itemCount)
        fixture.layOut(width: 1180)
        let collection = fixture.collection
        let original = collection.flowLayout
        let layout = TimedResizeFlowLayout()
        layout.sectionInset = original.sectionInset
        layout.minimumLineSpacing = original.minimumLineSpacing
        layout.minimumInteritemSpacing = original.minimumInteritemSpacing
        layout.itemSize = original.itemSize
        collection.setCollectionViewLayout(layout, animated: false)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        var frameTimes: [Double] = []
        var layoutTimes: [Double] = []
        for step in 0 ..< 65 {
            let before = layout.seconds
            let started = CACurrentMediaTime()
            _ = fixture.recordLiveResize(widths: [CGFloat(1180 - (step * 11) % 700)])
            let elapsed = CACurrentMediaTime() - started
            if step >= 5 {
                frameTimes.append(elapsed * 1000)
                layoutTimes.append((layout.seconds - before) * 1000)
            }
        }
        frameTimes.sort()
        layoutTimes.sort()
        let record: [String: Any] = [
            "scenario": "native-flow-layout", "items": itemCount, "frames": frameTimes.count,
            "frame_p50_ms": frameTimes[frameTimes.count / 2],
            "prepare_p50_ms": layoutTimes[layoutTimes.count / 2],
            "prepare_share_percent": 100 * layoutTimes.reduce(0, +) / frameTimes.reduce(0, +),
        ]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("RESIZE_DATA_UPDATE \(String(decoding: json, as: UTF8.self))")
    }

    @Test(arguments: [600, 10000, 100_000], [false, true])
    func `unchanged data updates`(itemCount: Int, identifiable: Bool) throws {
        let data = (0 ..< itemCount).map(UpdateItem.init)
        let layout = CollectionVGridLayout.minWidth(200)
        let grid = UICollectionVGrid(
            id: \UpdateItem.id, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil
        ) { _, _ in Color.blue.frame(height: 50) }
        if identifiable {
            grid.configure(CollectionVGrid(uniqueElements: data, layout: layout) { _, _ in Color.blue.frame(height: 50) })
        }
        func update() {
            grid.update(
                data: data,
                layout: layout,
                isScrollEnabled: true,
                verticalScrollIndicatorVisibility: .automatic,
                defersContentRefresh: true
            )
        }
        for _ in 0 ..< 20 {
            update()
        }
        for repetition in 0 ..< 3 {
            var samples: [Double] = []
            for _ in 0 ..< 200 {
                let started = CACurrentMediaTime()
                update()
                samples.append((CACurrentMediaTime() - started) * 1000)
            }
            samples.sort()
            let record: [String: Any] = [
                "scenario": identifiable ? "identifiable-data-update" : "unchanged-data-update", "items": itemCount,
                "repetition": repetition, "updates": samples.count,
                "p50_ms": samples[samples.count / 2],
                "p95_ms": samples[Int(Double(samples.count) * 0.95) - 1],
            ]
            let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            print("RESIZE_DATA_UPDATE \(String(decoding: json, as: UTF8.self))")
        }
    }
}

private struct UpdateItem: Identifiable {
    let id: Int
}

@MainActor
private final class TimedResizeFlowLayout: CollectionVGridFlowLayout {
    private(set) var seconds: CFTimeInterval = 0

    override func prepare() {
        let started = CACurrentMediaTime()
        super.prepare()
        seconds += CACurrentMediaTime() - started
    }
}
#endif
