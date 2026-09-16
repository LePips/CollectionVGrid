/// Stores identities without retaining elements. Ordinary arrays and slices need
/// only their start index; unusual Int-indexed collections retain their indices.
@usableFromInline
struct CollectionDataIndex<ID: Hashable> {
    @usableFromInline var storedIDs: [ID] = []
    @inlinable var ids: [ID] {
        storedIDs
    }

    @usableFromInline var startIndex = 0
    @usableFromInline var explicitIndices: [Int] = []

    /// The caller supplies an offset in the unrepeated, prefixed source.
    @inlinable @inline(__always)
    func sourceIndex(at offset: Int) -> Int {
        explicitIndices.isEmpty ? startIndex + offset : explicitIndices[offset]
    }

    /// Read from a borrowed contiguous buffer when available. Its offsets already
    /// account for slice bounds, so the common path needs no index translation.
    @inlinable @inline(__always)
    func element<Data: Collection>(in data: Data, at position: Int) -> Data.Element where Data.Index == Int {
        let offset = position < ids.count ? position : position % ids.count
        return data.withContiguousStorageIfAvailable { $0[offset] }
            ?? data[sourceIndex(at: offset)]
    }

    /// Resolve occasional identity queries without maintaining a second copy of
    /// every ID. Batch identity-based work should use makeLookup() instead.
    subscript(id: ID) -> Int? {
        ids.firstIndex(of: id).map { sourceIndex(at: $0) }
    }

    func makeLookup() -> [ID: Int] {
        Dictionary(uniqueKeysWithValues: ids.indices.lazy.map { (ids[$0], sourceIndex(at: $0)) })
    }

    static func uniqueOffsetLookup(for ids: [ID]) -> [ID: Int] {
        var lookup: [ID: Int] = [:]
        lookup.reserveCapacity(ids.count)
        for offset in ids.indices {
            precondition(
                lookup.updateValue(offset, forKey: ids[offset]) == nil,
                "Collection data requires unique element IDs"
            )
        }
        return lookup
    }

    /// A diff can still request a removed element. Nonnegative offsets refer to
    /// the new source; complemented offsets refer to the previous source. Using
    /// ordinal offsets also supports collections whose actual indices are negative.
    func includeRemovedOffsets(from previous: Self, in lookup: inout [ID: Int]) {
        for (offset, id) in previous.ids.enumerated() where lookup[id] == nil {
            lookup[id] = ~offset
        }
    }

    /// Extract each identity once. An unchanged update allocates no ID storage;
    /// on a change, copy only the already-compared ID prefix, never the elements.
    @discardableResult
    mutating func update<Data: Collection>(
        from data: Data, id: KeyPath<Data.Element, ID>, prefix: Int?
    ) -> Bool where Data.Index == Int {
        var unusedLookup: [ID: Int]?
        return update(from: data, id: id, prefix: prefix, buildLookup: false, lookup: &unusedLookup)
    }

    /// Structural updates need a lookup too. Validate uniqueness while building
    /// it, instead of hashing every ID once for a Set and again for a Dictionary.
    @discardableResult
    mutating func update<Data: Collection>(
        from data: Data, id: KeyPath<Data.Element, ID>, prefix: Int?, lookup: inout [ID: Int]?
    ) -> Bool where Data.Index == Int {
        update(from: data, id: id, prefix: prefix, buildLookup: true, lookup: &lookup)
    }

    /// AppKit snapshots resolve identities outside structural updates. Retain a
    /// lookup there, refreshing source indices even when only slice bounds change.
    @discardableResult
    mutating func update<Data: Collection>(
        from data: Data, id: KeyPath<Data.Element, ID>, prefix: Int?, retainingLookup lookup: inout [ID: Int]
    ) -> Bool where Data.Index == Int {
        let previousStart = startIndex
        let previousIndices = explicitIndices
        var changedLookup: [ID: Int]?
        let changed = update(from: data, id: id, prefix: prefix, lookup: &changedLookup)
        if let changedLookup {
            lookup = startIndex == 0 && explicitIndices.isEmpty
                ? changedLookup
                : changedLookup.mapValues { sourceIndex(at: $0) }
        } else if previousStart != startIndex || previousIndices != explicitIndices {
            lookup = makeLookup()
        }
        return changed
    }

    private mutating func update<Data: Collection>(
        from data: Data, id: KeyPath<Data.Element, ID>, prefix: Int?,
        buildLookup: Bool, lookup: inout [ID: Int]?
    ) -> Bool where Data.Index == Int {
        let limit = prefix ?? 0
        let values = limit > 0 ? data.prefix(limit) : data[..<data.endIndex]
        let changed = values.withContiguousStorageIfAvailable {
            updateIDs(from: $0, id: id)
        } ?? updateIDs(from: values, id: id)

        lookup = nil
        if changed {
            if buildLookup {
                lookup = Self.uniqueOffsetLookup(for: ids)
            } else {
                precondition(Set(ids).count == ids.count, "Collection data requires unique element IDs")
            }
        }
        startIndex = values.startIndex
        if values.indices is Range<Int> {
            explicitIndices = []
        } else {
            let indices = values.indices
            let contiguous = indices.enumerated().allSatisfy { $0.element == startIndex + $0.offset }
            if contiguous {
                explicitIndices = []
            } else if !explicitIndices.elementsEqual(indices) {
                explicitIndices = Array(indices)
            }
        }
        return changed
    }

    private mutating func updateIDs<Values: Sequence>(
        from values: Values, id: KeyPath<Values.Element, ID>
    ) -> Bool {
        let oldIDs = ids
        var replacementIDs: [ID] = []
        var changedIDs = false
        var count = 0
        for value in values {
            let valueID = value[keyPath: id]
            if !changedIDs, count >= oldIDs.count || oldIDs[count] != valueID {
                replacementIDs.reserveCapacity(max(oldIDs.count, values.underestimatedCount))
                replacementIDs.append(contentsOf: oldIDs.prefix(count))
                changedIDs = true
            }
            if changedIDs {
                replacementIDs.append(valueID)
            }
            count += 1
        }
        if !changedIDs, count != oldIDs.count {
            replacementIDs = Array(oldIDs.prefix(count))
            changedIDs = true
        }
        if changedIDs {
            storedIDs = replacementIDs
        }
        return changedIDs
    }
}
