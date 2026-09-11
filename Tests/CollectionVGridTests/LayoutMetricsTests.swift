@testable import CollectionVGrid
import SwiftUI
import Testing

struct LayoutMetricsTests {
    private let insets = EdgeInsets(top: 5, leading: 20, bottom: 7, trailing: 30)

    @Test
    func columnsConsumeAsymmetricInsetsAndInteritemSpacing() {
        let layout = CollectionVGridLayout.columns(3, insets: insets, itemSpacing: 10, lineSpacing: 70)
        let result = layout.itemWidth(for: 500)
        #expect(result.columns == 3)
        #expect(abs(result.width - 430 / 3) < 0.0001)
    }

    @Test
    func minimumWidthChangesColumnsAtTheSpacingBoundary() {
        let layout = CollectionVGridLayout.minWidth(100, insets: insets, itemSpacing: 10)
        #expect(layout.itemWidth(for: 259.9).columns == 1)
        #expect(abs(layout.itemWidth(for: 259.9).width - 209.9) < 0.0001)
        #expect(layout.itemWidth(for: 260).columns == 2)
        #expect(layout.itemWidth(for: 260).width == 100)
        #expect(layout.itemWidth(for: 70).columns == 1)
        #expect(layout.itemWidth(for: 70).width == 20)
        #expect(layout.itemWidth(for: 30).width == 0)
    }

    @Test
    func invalidConfigurationAndWidthsStayFinite() {
        for value: CGFloat in [0, -1, .nan, .infinity] {
            let layout = CollectionVGridLayout.minWidth(value, insets: insets, itemSpacing: value)
            #expect(layout.itemWidth(for: 500).columns == 450)
            #expect(layout.itemWidth(for: 500).width == 1)
            #expect(layout.itemWidth(for: value).columns == 1)
            #expect(layout.itemWidth(for: value).width == 0)
        }
        let invalid = CollectionVGridLayout.columns(0, insets: insets, itemSpacing: 10)
        #expect(invalid.itemWidth(for: 500).columns == 1)
        #expect(invalid.itemWidth(for: 500).width == 450)
        let huge = CollectionVGridLayout.columns(Int.max, insets: insets)
        #expect(huge.itemWidth(for: 500).columns > 0)
        #expect(huge.itemWidth(for: 500).width == 0)
    }
}

struct ItemSizeCacheTests {
    @Test
    func resizingReusesUnroundedContentProportions() {
        var cache = ItemSizeCache()
        var measurements = 0
        for width: CGFloat in [81.25, 100, 240.5] {
            let size = cache.size(width: width) {
                measurements += 1
                return CGSize(width: 81.25, height: 121.875)
            }
            #expect(size.width == width)
            #expect(abs(size.height - width * 1.5) < 0.0001)
        }
        #expect(measurements == 1)
    }

    @Test
    func invalidMeasurementsDoNotPoisonTheCache() {
        var cache = ItemSizeCache()
        var measurements = 0
        for height: CGFloat in [0, .nan, .infinity] {
            #expect(cache.size(width: 100) {
                measurements += 1
                return CGSize(width: 100, height: height)
            }.height == 0)
        }
        #expect(measurements == 3)
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 50) }.height == 50)
        #expect(cache.size(width: 200) { Issue.record("A valid ratio should be cached"); return .zero }.height == 100)
        cache = ItemSizeCache()
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 75) }.height == 75)
    }

    @Test
    func invalidWidthsNeverMeasureContent() {
        var cache = ItemSizeCache()
        for width: CGFloat in [0, -1, .nan, .infinity] {
            #expect(cache.size(width: width) { Issue.record("Invalid widths must not measure"); return .zero } == .zero)
        }
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 50) }.height == 50)
    }
}
