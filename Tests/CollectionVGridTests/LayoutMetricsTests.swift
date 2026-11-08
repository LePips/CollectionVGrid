@testable import CollectionVGrid
import SwiftUI
import Testing

struct LayoutMetricsTests {
    private let insets = EdgeInsets(top: 5, leading: 20, bottom: 7, trailing: 30)

    @Test
    func `columns consume asymmetric insets and interitem spacing`() {
        let layout = CollectionVGridLayout.columns(3, insets: insets, itemSpacing: 10, lineSpacing: 70)
        let result = layout.itemWidth(for: 500)
        #expect(result.columns == 3)
        #expect(abs(result.width - 430 / 3) < 0.0001)
    }

    @Test
    func `minimum width changes columns at the spacing boundary`() {
        let layout = CollectionVGridLayout.minWidth(100, insets: insets, itemSpacing: 10)
        #expect(layout.itemWidth(for: 259.9).columns == 1)
        #expect(abs(layout.itemWidth(for: 259.9).width - 209.9) < 0.0001)
        #expect(layout.itemWidth(for: 260).columns == 2)
        #expect(layout.itemWidth(for: 260).width == 100)
        #expect(layout.itemWidth(for: 70).columns == 1)
        #expect(layout.itemWidth(for: 70).width == 20)
        #expect(layout.itemWidth(for: 30).width == 0)
    }

    @Test(arguments: [2, 3, 4, 5, 10])
    func `minimum width respects adjacent floating point values at column boundaries`(columns: Int) {
        for minimum: CGFloat in [100, 100.1, 150, 161.25] {
            for spacing: CGFloat in [0, 10, 10.3] {
                let insets = EdgeInsets(top: 0, leading: 13.2, bottom: 0, trailing: 7.4)
                let layout = CollectionVGridLayout.minWidth(minimum, insets: insets, itemSpacing: spacing)
                let occupied = insets.leading + insets.trailing + CGFloat(columns - 1) * spacing
                let boundary = occupied + CGFloat(columns) * minimum
                #expect(layout.itemWidth(for: boundary.nextDown).columns == columns - 1)
                #expect(layout.itemWidth(for: boundary).columns == columns)
                #expect(layout.itemWidth(for: boundary.nextUp).columns == columns)
            }
        }
    }

    @Test
    func `invalid configuration and widths stay finite`() {
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
    func `content caches only the current exact width and preserves wrapping transitions`() {
        var cache = ItemSizeCache()
        var measurements = 0
        for width: CGFloat in [200, 199.999, 200.001, 150, 300, 200] {
            let expectedHeight = width * 1.5 + (width < 200 ? 48 : 24) + 7
            for _ in 0 ..< 1000 {
                let size = cache.size(width: width) {
                    measurements += 1
                    return CGSize(width: width, height: expectedHeight)
                }
                #expect(size == CGSize(width: width, height: expectedHeight))
            }
        }
        #expect(measurements == 6, "Thousands of items share one measurement per exact width")
    }

    @Test
    func `content invalid measurements are retried at the same width`() {
        var cache = ItemSizeCache()
        for height: CGFloat in [0, -1, .nan, .infinity] {
            #expect(cache.size(width: 100) { CGSize(width: 100, height: height) }.height == 0)
        }
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 181) }.height == 181)
        #expect(cache.size(width: 100) {
            Issue.record("Valid content height should be shared at the same width")
            return .zero
        }.height == 181)
    }

    @Test(arguments: [CollectionVGridLayout.ItemSizing.aspectRatio, .height])
    func `resizing reuses unrounded content measurement`(sizing: CollectionVGridLayout.ItemSizing) {
        var cache = ItemSizeCache()
        var measurements = 0
        for width: CGFloat in [81.25, 100, 240.5] {
            let size = cache.size(width: width, sizing: sizing) {
                measurements += 1
                return CGSize(width: 81.25, height: 121.875)
            }
            #expect(size.width == width)
            let expectedHeight = sizing == .height ? 121.875 : width * 1.5
            #expect(abs(size.height - expectedHeight) < 0.0001)
        }
        #expect(measurements == 1)
    }

    @Test(arguments: [CollectionVGridLayout.ItemSizing.aspectRatio, .height])
    func `invalid measurements do not poison the cache`(sizing: CollectionVGridLayout.ItemSizing) {
        var cache = ItemSizeCache()
        var measurements = 0
        for height: CGFloat in [0, -1, .nan, .infinity] {
            #expect(cache.size(width: 100, sizing: sizing) {
                measurements += 1
                return CGSize(width: 100, height: height)
            }.height == 0)
        }
        #expect(measurements == 4)
        #expect(cache.size(width: 100, sizing: sizing) { CGSize(width: 100, height: 50) }.height == 50)
        let resized = cache.size(width: 200, sizing: sizing) {
            Issue.record("A valid measurement should be cached")
            return .zero
        }
        #expect(resized.height == (sizing == .height ? 50 : 100))
        cache = ItemSizeCache()
        #expect(cache.size(width: 100, sizing: sizing) { CGSize(width: 100, height: 75) }.height == 75)
    }

    @Test(arguments: [CollectionVGridLayout.ItemSizing.aspectRatio, .height])
    func `invalid widths never measure content`(sizing: CollectionVGridLayout.ItemSizing) {
        var cache = ItemSizeCache()
        for width: CGFloat in [0, -1, .nan, .infinity] {
            #expect(cache.size(width: width, sizing: sizing) { Issue.record("Invalid widths must not measure")
                return .zero
            } == .zero)
        }
        #expect(cache.size(width: 100, sizing: sizing) { CGSize(width: 100, height: 50) }.height == 50)
    }

    @Test
    func `changing sizing remeasures instead of reinterpreting the cached value`() {
        var cache = ItemSizeCache()
        #expect(cache.size(width: 100, sizing: .aspectRatio) { CGSize(width: 100, height: 50) }.height == 50)
        #expect(cache.size(width: 200, sizing: .height) { CGSize(width: 200, height: 75) }.height == 75)
        #expect(cache.size(width: 100, sizing: .aspectRatio) { CGSize(width: 100, height: 40) }.height == 40)
        #expect(cache.size(width: 200, sizing: .aspectRatio) { Issue.record("The new ratio should be cached")
            return .zero
        }.height == 80)
    }
}
