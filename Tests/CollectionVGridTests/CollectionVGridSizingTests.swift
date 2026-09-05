@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionVGridSizingTests {

    @Test
    func contentMeasurementIsCachedAcrossResizeWidths() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter)

        grid.bounds = CGRect(x: 0, y: 0, width: 210, height: 500)
        grid.layoutSubviews()
        grid.layoutSubviews()

        #expect(counter.value == 1)

        grid.bounds.size.width = 410
        grid.layoutSubviews()

        #expect(counter.value == 1)
    }

    @Test
    func measuredProportionsDetermineHeightForEveryResizeWidth() {
        let grid = makeGrid(counter: MeasurementCounter())

        let initialSize = grid.computeItemSize(forWidth: 210)
        let resizedSize = grid.computeItemSize(forWidth: 410)

        #expect(initialSize.columns == 2)
        #expect(initialSize.itemSize == CGSize(width: 100, height: 50))
        #expect(resizedSize.columns == 2)
        #expect(resizedSize.itemSize == CGSize(width: 200, height: 100))
    }

    @Test
    func fractionalWidthMeasurementPreservesContentProportions() {
        let grid = makeMutableAspectRatioGrid(aspectRatio: MutableAspectRatio(2 / 3), proxy: .init())
        #expect(abs(grid.computeItemSize(forWidth: 550 / 3).itemSize.height - 130) <= 0.001)
        #expect(abs(grid.computeItemSize(forWidth: 810).itemSize.height - 600) <= 0.001)
    }

    @Test
    func dataChangesAndDynamicTypeRemeasureContent() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter)
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 50)
        #expect(grid.computeItemSize(forWidth: 410).itemSize.height == 100)
        grid.update(
            data: [1],
            layout: .columns(2, insets: .init(), itemSpacing: 10, lineSpacing: 10),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
        )
        #expect(grid.computeItemSize(forWidth: 410).itemSize.height == 50)
        #expect(counter.value == 2)
        grid.traitCollectionDidChange(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 50)
        #expect(counter.value == 3)
    }

    @Test
    func zeroWidthDoesNotCreateAMeasurement() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter)
        #expect(grid.computeItemSize(forWidth: 0).itemSize.height == 0)
        #expect(counter.value == 0)
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 50)
        #expect(grid.computeItemSize(forWidth: 410).itemSize.height == 100)
        #expect(counter.value == 1)
    }

    @Test
    func zeroHeightDoesNotCacheInvalidProportions() {
        let counter = MeasurementCounter()
        counter.height = 0
        let grid = makeGrid(counter: counter)
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 0)
        counter.height = 50
        #expect(grid.computeItemSize(forWidth: 410).itemSize.height == 50)
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 25)
        #expect(counter.value == 2)
    }

    @Test
    func emptyCollectionMeasuresWhenDataArrives() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter, data: [])
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 0)
        #expect(counter.value == 0)
        grid.update(
            data: [0],
            layout: .columns(2, insets: .init(), itemSpacing: 10, lineSpacing: 10),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic
        )
        #expect(grid.computeItemSize(forWidth: 210).itemSize.height == 50)
        #expect(grid.computeItemSize(forWidth: 410).itemSize.height == 100)
        #expect(counter.value == 1)
    }

    @Test
    func resizeDerivesProportionsFromMeasuredContent() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter)

        #expect(grid.computeItemSize(forWidth: 210).itemSize == CGSize(width: 100, height: 50))
        #expect(grid.computeItemSize(forWidth: 410).itemSize == CGSize(width: 200, height: 100))

        #expect(counter.value == 1)
    }

    @Test
    func proxyRedrawRemeasuresAContentDefinedAspectRatio() throws {
        let aspectRatio = MutableAspectRatio(2 / 3)
        let proxy = CollectionVGridProxy()
        let grid = makeMutableAspectRatioGrid(aspectRatio: aspectRatio, proxy: proxy)
        grid.bounds = CGRect(x: 0, y: 0, width: 210, height: 500)
        grid.layoutSubviews()

        let collectionView = try #require(
            grid.subviews.compactMap { $0 as? UICollectionView }.first
        )
        let initialSize = grid.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        aspectRatio.value = 1
        #expect(grid.computeItemSize(forWidth: 410).itemSize == CGSize(width: 200, height: 300))
        proxy.redraw()

        let redrawnSize = grid.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        #expect(initialSize == CGSize(width: 100, height: 150))
        #expect(redrawnSize == CGSize(width: 100, height: 100))
        #expect(grid.computeItemSize(forWidth: 410).itemSize == CGSize(width: 200, height: 200))
        aspectRatio.value = 2
        proxy.redraw()
        #expect(grid.computeItemSize(forWidth: 410).itemSize == CGSize(width: 200, height: 100))
    }

    @Test
    func widthOnlyResizeUpdatesFlowLayoutAndResolvedItemWidth() throws {
        let grid = makeGrid(counter: MeasurementCounter())
        let layout = CollectionVGridLayout.columns(
            2,
            insets: .init(),
            itemSpacing: 10,
            lineSpacing: 10
        )

        grid.update(
            data: [0],
            layout: layout,
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic
        )

        grid.bounds = CGRect(x: 0, y: 0, width: 210, height: 500)
        grid.layoutSubviews()

        let collectionView = try #require(
            grid.subviews.compactMap { $0 as? UICollectionView }.first
        )
        let initialItemSize = grid.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        grid.bounds.size.width = 210.2
        grid.layoutSubviews()

        let resizedItemSize = grid.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        #expect(initialItemSize.width == 100)
        #expect(abs(initialItemSize.height - 50) <= 0.001)
        #expect(abs(resizedItemSize.width - 100.1) <= 0.001)
        #expect(abs(resizedItemSize.height - 50.05) <= 0.001)
        #expect(collectionView.flowLayout.itemSize == resizedItemSize)
        #expect(try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )
        ).size == resizedItemSize)
    }

    @Test
    func minimumWidthUsesOneColumnWhenContainerIsNarrowerThanMinimum() {
        let grid = makeGrid(
            counter: MeasurementCounter(),
            layout: .minWidth(
                200,
                insets: .init(),
                itemSpacing: 10,
                lineSpacing: 10
            )
        )

        let size = grid.computeItemSize(forWidth: 100)

        #expect(size.columns == 1)
        #expect(size.itemSize == CGSize(width: 100, height: 50))
    }

    @Test
    func invalidSizingInputsFallBackWithoutProducingInvalidDimensions() {
        let counter = MeasurementCounter()
        let invalidColumnsGrid = makeGrid(
            counter: counter,
            layout: .columns(
                0,
                insets: .init(),
                itemSpacing: 10,
                lineSpacing: 10
            )
        )

        let columnsSize = invalidColumnsGrid.computeItemSize(forWidth: 100)

        #expect(columnsSize.columns == 1)
        #expect(columnsSize.itemSize == CGSize(width: 100, height: 50))
        #expect(counter.value == 1)

        let invalidMinimumGrid = makeGrid(
            counter: MeasurementCounter(),
            layout: .minWidth(
                .nan,
                insets: .init(),
                itemSpacing: 10,
                lineSpacing: 10
            )
        )
        let minimumSize = invalidMinimumGrid.computeItemSize(forWidth: 100)

        #expect(minimumSize.itemSize.width.isFinite)
        #expect(minimumSize.itemSize.height.isFinite)
        #expect(minimumSize.itemSize.width >= 0)
        #expect(minimumSize.itemSize.height >= 0)
    }

    @Test
    func largeCollectionResizePerformance() {
        let counter = MeasurementCounter()
        let grid = makeGrid(counter: counter, data: Array(0 ..< 10000))
        let duration = ContinuousClock().measure {
            for step in 0 ..< 120 {
                let width = CGFloat(320 + step * 8)
                _ = grid.computeItemSize(forWidth: width)
            }
        }
        print("CollectionVGrid: 120 resizes with 10,000 items took \(duration)")
        #expect(counter.value == 1, "Resizing must reuse the initial content measurement")
    }

    @Test
    func redrawUsesUpdatedContentProvider() {
        let original = MeasurementCounter()
        let replacement = MeasurementCounter()
        let grid = makeGrid(counter: original)
        grid.bounds = CGRect(x: 0, y: 0, width: 210, height: 500)
        grid.layoutSubviews()
        grid.update(
            data: [0],
            layout: .columns(2, insets: .init(), itemSpacing: 10, lineSpacing: 10),
            isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic,
            viewProvider: { _, _ in MeasuredItem(counter: replacement) }
        )
        grid.snapshotReload()
        grid.layoutSubviews()
        #expect(original.value == 1)
        #expect(replacement.value > 0)
    }

    private func makeGrid(
        counter: MeasurementCounter,
        layout: CollectionVGridLayout = .columns(
            2,
            insets: .init(),
            itemSpacing: 10,
            lineSpacing: 10
        ),
        data: [Int] = [0]
    ) -> UICollectionVGrid<Int, [Int], Int, MeasuredItem> {
        UICollectionVGrid(
            id: \.self,
            data: data,
            layout: layout,
            onReachedBottomEdge: {},
            onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {},
            onReachedTopEdgeOffset: .rows(0),
            proxy: nil,
            viewProvider: { _, _ in MeasuredItem(counter: counter) }
        )
    }

    private func makeMutableAspectRatioGrid(
        aspectRatio: MutableAspectRatio,
        proxy: CollectionVGridProxy
    ) -> UICollectionVGrid<Int, [Int], Int, MutableAspectRatioItem> {
        UICollectionVGrid(
            id: \.self,
            data: [0],
            layout: .columns(
                2,
                insets: .init(),
                itemSpacing: 10,
                lineSpacing: 10
            ),
            onReachedBottomEdge: {},
            onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {},
            onReachedTopEdgeOffset: .rows(0),
            proxy: proxy,
            viewProvider: { _, _ in MutableAspectRatioItem(aspectRatio: aspectRatio.value) }
        )
    }
}

private final class MeasurementCounter {
    var value = 0
    var height: CGFloat = 50
}

private struct MeasuredItem: View {
    private let height: CGFloat

    init(counter: MeasurementCounter) {
        counter.value += 1
        height = counter.height
    }

    var body: some View {
        Color.blue.frame(height: height)
    }
}

private final class MutableAspectRatio {
    var value: CGFloat

    init(_ value: CGFloat) {
        self.value = value
    }
}

private struct MutableAspectRatioItem: View {
    let aspectRatio: CGFloat

    var body: some View {
        Color.blue.aspectRatio(aspectRatio, contentMode: .fill)
    }
}
