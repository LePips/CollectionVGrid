@testable import CollectionVGrid
import Foundation
import Testing

struct UtilitiesTests {
    @Test
    func clampingHandlesBoundsAndCollapsedRanges() {
        #expect(Int.min.clamped(to: -10 ... 10) == -10)
        #expect(Int.max.clamped(to: -10 ... 10) == 10)
        #expect((-10).clamped(to: -10 ... 10) == -10)
        #expect(10.clamped(to: -10 ... 10) == 10)
        #expect(3.clamped(to: -10 ... 10) == 3)
        #expect(100.clamped(to: 0 ... 0) == 0)
        #expect(CGFloat(0.25).clamped(to: 0 ... 1) == 0.25)
        #expect(CGFloat.infinity.clamped(to: 0 ... 1) == 1)
        #expect((-CGFloat.infinity).clamped(to: 0 ... 1) == 0)
    }

    @Test
    func dimensionValidationHandlesInvalidValuesWithoutRoundingFractions() {
        for value: CGFloat in [.nan, .infinity, -.infinity, -1, 0] {
            #expect(!value.isFiniteAndPositive)
            #expect(value.positiveFinite(or: 1) == 1)
            #expect(nonnegativeFinite(value) == 0)
        }
        for value: CGFloat in [0.25, 1, 100, .greatestFiniteMagnitude] {
            #expect(value.isFiniteAndPositive)
            #expect(value.positiveFinite(or: 1) == value)
            #expect(nonnegativeFinite(value) == value)
        }
    }
}
