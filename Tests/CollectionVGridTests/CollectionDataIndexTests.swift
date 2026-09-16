#if canImport(CollectionHStack)
@testable import CollectionHStack
#else
@testable import CollectionVGrid
#endif
import Testing

struct CollectionDataIndexTests {
    private struct Value {
        let id: Int
        let content: String
    }

    @Test
    func unchangedIdentitiesReuseStorageAndResolveNewContent() throws {
        var index = CollectionDataIndex<Int>()
        let first = [Value(id: 1, content: "old"), Value(id: 2, content: "old")]
        let inserted = index.update(from: first, id: \.id, prefix: nil)
        #expect(inserted)
        // Hold the original buffer alive so a rebuild cannot reuse its address.
        let originalIDs = index.ids
        let next = [Value(id: 1, content: "new"), Value(id: 2, content: "new")]
        let changedContent = index.update(from: next, id: \.id, prefix: nil)
        #expect(!changedContent)
        originalIDs.withUnsafeBufferPointer { original in
            index.ids.withUnsafeBufferPointer { current in
                #expect(original.baseAddress == current.baseAddress)
            }
        }
        #expect(try next[#require(index[2])].content == "new")
    }

    @Test
    func sameIDsAtDifferentSliceIndicesReuseIDsAndRefreshLookups() throws {
        var index = CollectionDataIndex<Int>()
        let first = [0, 1, 2, 3, 4][2 ..< 5]
        let inserted = index.update(from: first, id: \.self, prefix: 2)
        #expect(inserted)
        #expect(index.ids == [2, 3])
        #expect(index[2] == 2)
        #expect(index[4] == nil)
        let originalIDs = index.ids
        let next = [2, 3][...]
        let shiftedIndices = index.update(from: next, id: \.self, prefix: nil)
        #expect(!shiftedIndices)
        #expect(index[2] == 0)
        #expect(index[3] == 1)
        #expect(try next[#require(index[3])] == 3)
        originalIDs.withUnsafeBufferPointer { original in
            index.ids.withUnsafeBufferPointer { current in
                #expect(original.baseAddress == current.baseAddress)
            }
        }
    }

    @Test
    func reorderInsertionDeletionAndEmptyDataReplaceMetadata() {
        var index = CollectionDataIndex<Int>()
        let inserted = index.update(from: [1, 2, 3], id: \.self, prefix: nil)
        #expect(inserted)
        let reordered = index.update(from: [3, 4, 1], id: \.self, prefix: nil)
        #expect(reordered)
        #expect(index.ids == [3, 4, 1])
        #expect(index[3] == 0)
        #expect(index[4] == 1)
        #expect(index[1] == 2)
        #expect(index[2] == nil)
        let removed = index.update(from: [Int](), id: \.self, prefix: nil)
        #expect(removed)
        #expect(index.ids.isEmpty)
        #expect(index[1] == nil)
        let stillEmpty = index.update(from: [Int](), id: \.self, prefix: nil)
        #expect(!stillEmpty)
    }

    @Test
    func noncontiguousIndicesAndUnlimitedPrefixes() {
        let data = SpacedCollection()
        for prefix: Int? in [nil, 0, -1, 100] {
            var index = CollectionDataIndex<Int>()
            let inserted = index.update(from: data, id: \.self, prefix: prefix)
            #expect(inserted)
            #expect(index.ids == [20, 40, 60])
            #expect(index[20] == 2)
            #expect(index[40] == 4)
            #expect(index[60] == 6)
        }
    }

    @Test
    func extractsEveryIDOnceAndReadsByPositionWithoutExtractingIDs() {
        final class Reads { var count = 0 }
        struct CountedCollection: Collection {
            let values: [Value]
            let reads: Reads
            var startIndex: Int {
                values.startIndex
            }

            var endIndex: Int {
                values.endIndex
            }

            func index(after i: Int) -> Int {
                i + 1
            }

            subscript(index: Int) -> Value {
                reads.count += 1
                return values[index]
            }
        }
        let reads = Reads()
        let data = CountedCollection(values: (0 ..< 100).map { Value(id: $0, content: "value") }, reads: reads)
        var index = CollectionDataIndex<Int>()
        index.update(from: data, id: \.id, prefix: 10)
        #expect(reads.count == 10)
        #expect(index.explicitIndices.isEmpty)
        reads.count = 0
        index.update(from: data, id: \.id, prefix: 10)
        #expect(reads.count == 10)
        reads.count = 0
        for offset in index.ids.indices {
            #expect(data[index.sourceIndex(at: offset)].id == offset)
        }
        #expect(reads.count == 10)
    }

    @Test
    func irregularIndicesRemainIndependentAcrossUpdates() {
        struct IrregularCollection: Collection {
            let positions: [Int]
            let values: [Int]
            var startIndex: Int {
                positions[0]
            }

            var endIndex: Int {
                positions[positions.count - 1] + 1
            }

            func index(after i: Int) -> Int {
                guard let current = positions.firstIndex(of: i) else { preconditionFailure("Invalid source index") }
                let offset = current + 1
                return offset < positions.count ? positions[offset] : endIndex
            }

            subscript(index: Int) -> Int {
                guard let offset = positions.firstIndex(of: index) else { preconditionFailure("Invalid source index") }
                return values[offset]
            }
        }
        var index = CollectionDataIndex<Int>()
        let first = IrregularCollection(positions: [-7, 2, 50], values: [1, 2, 3])
        index.update(from: first, id: \.self, prefix: nil)
        let old = index
        #expect(index.explicitIndices == first.positions)
        let unchanged = index.update(from: first, id: \.self, prefix: nil)
        #expect(!unchanged)
        old.explicitIndices.withUnsafeBufferPointer { previous in
            index.explicitIndices.withUnsafeBufferPointer { current in
                #expect(previous.baseAddress == current.baseAddress)
            }
        }
        let shifted = IrregularCollection(positions: [20, 21, 29], values: [1, 2, 3])
        let changedIndices = index.update(from: shifted, id: \.self, prefix: nil)
        #expect(!changedIndices)
        #expect(index.makeLookup() == [1: 20, 2: 21, 3: 29])
        #expect(old.makeLookup() == [1: -7, 2: 2, 3: 50])
        let contiguous = index.update(from: [1, 2, 3], id: \.self, prefix: nil)
        #expect(!contiguous)
        #expect(index.explicitIndices.isEmpty)
        #expect(index.makeLookup() == [1: 0, 2: 1, 3: 2])
    }

    @Test
    func borrowedBuffersRespectSliceBoundsPrefixesAndPartialRepetitions() {
        let values = (0 ..< 12).map { Value(id: $0, content: "value-\($0)") }
        let slice = values[3 ..< 10]
        var index = CollectionDataIndex<Int>()
        index.update(from: slice, id: \.id, prefix: 3)
        for position in 0 ..< 100 {
            #expect(index.element(in: slice, at: position).id == 3 + position % 3)
        }
        let updated = (3 ..< 6).map { Value(id: $0, content: "updated") }
        let changed = index.update(from: updated[...], id: \.id, prefix: nil)
        #expect(!changed)
        for position in 0 ..< 100 {
            #expect(index.element(in: updated[...], at: position).content == "updated")
        }
    }

    @Test
    func directReadsSupportNoncontiguousIndicesAndOptionalElements() {
        let data = SpacedCollection()
        var index = CollectionDataIndex<Int>()
        index.update(from: data, id: \.self, prefix: nil)
        for position in 0 ..< 100 {
            #expect(index.element(in: data, at: position) == [20, 40, 60][position % 3])
        }
        let optionals: [Int?] = [nil, 1, 2]
        var optionalIndex = CollectionDataIndex<Int?>()
        optionalIndex.update(from: optionals, id: \.self, prefix: nil)
        #expect(optionalIndex.element(in: optionals, at: 3) == nil)
        #expect(optionalIndex.element(in: optionals, at: 4) == 1)
    }

    @Test
    func transitionLookupUsesNewContentAndRetainsRemovedOffsets() throws {
        var previous = CollectionDataIndex<Int>()
        previous.update(from: [1, 2, 3, 4][1...], id: \.self, prefix: nil)
        var current = CollectionDataIndex<Int>()
        var changedLookup: [Int: Int]?
        current.update(from: [4, 2, 5], id: \.self, prefix: nil, lookup: &changedLookup)
        var lookup = try #require(changedLookup)
        current.includeRemovedOffsets(from: previous, in: &lookup)
        #expect(lookup[4] == 0)
        #expect(lookup[2] == 1)
        #expect(lookup[5] == 2)
        #expect(lookup[3] == ~1)
        #expect(changedLookup == [4: 0, 2: 1, 5: 2])
        current.update(from: [4, 2, 5], id: \.self, prefix: nil, lookup: &changedLookup)
        #expect(changedLookup == nil)
        let empty = CollectionDataIndex<Int>()
        var removed: [Int: Int] = [:]
        empty.includeRemovedOffsets(from: previous, in: &removed)
        #expect(removed == [2: ~0, 3: ~1, 4: ~2])
    }

    @Test
    func identityLookupHandlesHashCollisions() {
        struct ID: Hashable {
            let value: Int
            func hash(into hasher: inout Hasher) {
                hasher.combine(0)
            }
        }
        let values = (0 ..< 100).map(ID.init(value:))
        var index = CollectionDataIndex<ID>()
        index.update(from: values, id: \.self, prefix: nil)
        let lookup = index.makeLookup()
        for offset in values.indices {
            #expect(lookup[values[offset]] == offset)
            #expect(index.sourceIndex(at: offset) == offset)
        }
    }

    @Test
    func retainedLookupFollowsSourceIndicesAndContentWithoutRebuildingIDs() {
        var index = CollectionDataIndex<Int>()
        var lookup: [Int: Int] = [:]
        let values = (0 ..< 5).map { Value(id: $0, content: "old") }
        let inserted = index.update(from: values[2...], id: \.id, prefix: nil, retainingLookup: &lookup)
        #expect(inserted)
        #expect(lookup == [2: 2, 3: 3, 4: 4])
        let originalIDs = index.ids
        let next = values[2...].map { Value(id: $0.id, content: "new") }
        let changed = index.update(from: next[...], id: \.id, prefix: nil, retainingLookup: &lookup)
        #expect(!changed)
        #expect(lookup == [2: 0, 3: 1, 4: 2])
        originalIDs.withUnsafeBufferPointer { old in
            index.ids.withUnsafeBufferPointer { current in #expect(old.baseAddress == current.baseAddress) }
        }
        #expect(index.element(in: next[...], at: 1).content == "new")
        let removed = index.update(from: [Value]()[...], id: \.id, prefix: nil, retainingLookup: &lookup)
        #expect(removed)
        #expect(lookup.isEmpty)
    }

    @Test
    func metadataDoesNotRetainElements() {
        final class Element {
            let id = 1
        }
        var index = CollectionDataIndex<Int>()
        weak var reference: Element?
        do {
            let element = Element()
            reference = element
            index.update(from: [element], id: \.id, prefix: nil)
        }
        #expect(reference == nil)
        #expect(index.ids == [1])
    }
}

private struct SpacedCollection: Collection {
    let startIndex = 2
    let endIndex = 8
    func index(after i: Int) -> Int {
        i + 2
    }

    subscript(index: Int) -> Int {
        precondition(index >= startIndex && index < endIndex && index.isMultiple(of: 2))
        return index * 10
    }
}
