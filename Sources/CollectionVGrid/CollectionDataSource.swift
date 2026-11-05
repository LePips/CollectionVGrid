/// Identity metadata only; repeated positions never retain another element copy.
@usableFromInline
struct CollectionItem<ID: Hashable> {

    @usableFromInline
    struct Identity: Hashable {

        let id: ID
        let repetition: Int
    }

    @usableFromInline
    let id: ID
    @usableFromInline
    let repetition: Int

    @usableFromInline
    var identity: Identity {
        Identity(id: id, repetition: repetition)
    }

    @inlinable
    init(id: ID, repetition: Int = 0) {
        self.id = id
        self.repetition = repetition
    }
}

extension CollectionDataIndex {

    @inlinable
    func item(at position: Int) -> CollectionItem<ID> {
        CollectionItem(id: ids[position % ids.count], repetition: position / ids.count)
    }

    func items(count: Int? = nil) -> CollectionSnapshot<ID> {
        CollectionSnapshot(ids: ids, count: count)
    }
}

/// Owns the old source only while a staged update can request removed identities.
/// Surviving identities always resolve against the latest source, including new content.
struct CollectionDataTransition<Data: Collection, ID: Hashable> where Data.Index == Int {

    private let previousData: Data
    private let previousIndex: CollectionDataIndex<ID>
    private var indices: [ID: Int]

    init(
        previousData: Data,
        previousIndex: CollectionDataIndex<ID>,
        currentIndex: CollectionDataIndex<ID>,
        lookup: inout [ID: Int]?,
        hasDeletions: Bool
    ) {
        self.previousData = previousData
        self.previousIndex = previousIndex
        indices = lookup ?? CollectionDataIndex.uniqueOffsetLookup(for: currentIndex.ids)
        // Relinquish the caller's reference before adding removed IDs to avoid COW.
        lookup = nil
        if hasDeletions {
            currentIndex.includeRemovedOffsets(from: previousIndex, in: &indices)
        }
    }

    func element(for id: ID, in data: Data, index: CollectionDataIndex<ID>) -> Data.Element {
        guard let offset = indices[id] else {
            preconditionFailure("A staged identity must exist in the current or previous source")
        }

        if offset >= 0 {
            return index.element(in: data, at: offset)
        }
        return previousIndex.element(in: previousData, at: ~offset)
    }
}
