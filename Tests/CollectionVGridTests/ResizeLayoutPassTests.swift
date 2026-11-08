#if canImport(UIKit)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ResizeLayoutPassTests {
    @Test(arguments: [17, 100_001])
    func `uniform sizing keeps distant rows correct after resizing`(itemCount: Int) throws {
        let layout = CollectionVGridLayout.minWidth(200, insets: .init(), itemSpacing: 10, lineSpacing: 10)
        let data = Array(0 ..< itemCount)
        let grid = UICollectionVGrid(
            id: \.self, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { _, _ in Color.blue.frame(height: 50) }
        grid.update(data: data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        grid.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        grid.layoutIfNeeded()
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.numberOfItems(inSection: 0) == itemCount)

        // Advertising this optional selector forces UIKit to request the same
        // size for every item during preparation, even for offscreen rows.
        #expect(!grid.responds(to: #selector(UICollectionViewDelegateFlowLayout.collectionView(_:layout:sizeForItemAt:))))
        for width: CGFloat in [1180, 850.25, 850, 849.75, 390, 1180] {
            grid.frame.size.width = width
            grid.layoutIfNeeded()
            collection.layoutIfNeeded()
            let expected = layout.itemWidth(for: width)
            for index in [0, expected.columns - 1, expected.columns, itemCount / 2, itemCount - 1] {
                let attributes = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(
                    item: index,
                    section: 0
                )))
                #expect(abs(attributes.size.width - expected.width) <= 0.5)
                #expect(attributes.size.height == 50)
                #expect(abs(attributes.frame.minY - CGFloat(index / expected.columns) * 60) <= 0.5)
            }
            let rows = (itemCount + expected.columns - 1) / expected.columns
            #expect(abs(collection.contentSize.height - CGFloat(rows * 60 - 10)) <= 0.5)
        }
    }

    @Test(arguments: [true, false])
    func `each resize layout pass uses the current width`(adaptiveColumns: Bool) throws {
        let layout = adaptiveColumns ? CollectionVGridLayout.minWidth(180) : .columns(3)
        let data = Array(0 ..< 16)
        let grid = UICollectionVGrid(
            id: \.self, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { _, _ in
            Color.blue.aspectRatio(16 / 9, contentMode: .fit)
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = controller
        controller.view.addSubview(grid)
        grid.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(data: data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        controller.view.layoutIfNeeded()

        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        // The caller animates its own safe-area padding around the collection.
        collection.contentInsetAdjustmentBehavior = .never
        let recording = RecordingResizeFlowLayout()
        recording.sectionInset = collection.flowLayout.sectionInset
        recording.minimumLineSpacing = collection.flowLayout.minimumLineSpacing
        recording.minimumInteritemSpacing = collection.flowLayout.minimumInteritemSpacing
        recording.itemSize = collection.flowLayout.itemSize
        collection.setCollectionViewLayout(recording, animated: false)
        collection.layoutIfNeeded()
        recording.measurements.removeAll()

        // Include fractional widths on both sides of the four/five/six-column
        // boundaries crossed by an iPad sidebar animation, in both directions.
        let widths: [CGFloat] = [1180, 1179.5, 1160, 1150.5, 1150, 1149.5, 1100, 1000, 960, 959.5, 900, 860]
        for width in widths + widths.reversed() {
            // During expansion the sidebar's safe area also reaches into the
            // collection until its outer padding finishes animating.
            controller.additionalSafeAreaInsets.left = max(0, width - 860)
            grid.frame.size.width = width
            // A scene/SwiftUI geometry update can lay out the child before the
            // wrapper receives layoutSubviews. Its first pass must already fit.
            collection.frame.size.width = width
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            #expect(collection.adjustedContentInset.left == 0)
            #expect(collection.adjustedContentInset.right == 0)
            grid.setNeedsLayout()
            grid.layoutIfNeeded()
            collection.layoutIfNeeded()
        }

        #expect(!recording.measurements.isEmpty)
        for measurement in recording.measurements {
            let expected = layout.itemWidth(for: measurement.containerWidth)
            #expect(
                abs(measurement.itemWidth - expected.width) < 0.001,
                "Layout at width \(measurement.containerWidth) used item width \(measurement.itemWidth), expected \(expected.width)"
            )
            #expect(measurement.frames.count == data.count)
            for (index, frame) in measurement.frames.enumerated() {
                #expect(abs(frame.width - expected.width) <= 0.5)
                let expectedRow = index / expected.columns
                let firstInRow = expectedRow * expected.columns
                #expect(
                    frame.minY == measurement.frames[firstInRow].minY,
                    "Item \(index) was placed on the wrong row at width \(measurement.containerWidth)"
                )
                if firstInRow > 0 {
                    #expect(frame.minY > measurement.frames[firstInRow - 1].minY)
                }
            }
        }
    }
}

@MainActor
private final class RecordingResizeFlowLayout: CollectionVGridFlowLayout {
    struct Measurement {
        let containerWidth: CGFloat
        let itemWidth: CGFloat
        let frames: [CGRect]
    }

    var measurements: [Measurement] = []

    override func prepare() {
        super.prepare()
        if let collectionView {
            let size = itemSize
            let frames = (0 ..< collectionView.numberOfItems(inSection: 0)).compactMap {
                super.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
            }
            measurements.append(.init(containerWidth: collectionView.bounds.width, itemWidth: size.width, frames: frames))
        }
    }
}
#endif
