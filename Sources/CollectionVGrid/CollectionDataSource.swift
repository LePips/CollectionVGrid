import DifferenceKit

/// Identity metadata only; repeated positions never retain another element copy.
@usableFromInline
struct CollectionItem<ID: Hashable>: Differentiable {
    @usableFromInline let id: ID
    @usableFromInline var repetition: Int

    @inlinable
    init(id: ID, repetition: Int = 0) {
        self.id = id
        self.repetition = repetition
    }

    @usableFromInline
    struct Identity: Hashable {
        let id: ID
        let repetition: Int
    }

    @usableFromInline
    var differenceIdentifier: Identity {
        Identity(id: id, repetition: repetition)
    }

    @usableFromInline
    func isContentEqual(to source: Self) -> Bool {
        true
    }
}

extension CollectionDataIndex {
    @inlinable
    func item(at position: Int) -> CollectionItem<ID> {
        CollectionItem(id: ids[position % ids.count], repetition: position / ids.count)
    }

    /// Materialize identities only when the native view requires a structural diff.
    @inlinable
    func items(count: Int? = nil) -> [CollectionItem<ID>] {
        (0 ..< (count ?? ids.count)).map { item(at: $0) }
    }
}

/// Owns the old source only while DifferenceKit can request removed identities.
/// Surviving identities always resolve against the latest source, including new content.
struct CollectionDataTransition<Data: Collection, ID: Hashable> where Data.Index == Int {
    private let previousData: Data
    private let previousIndex: CollectionDataIndex<ID>
    private var indices: [ID: Int]

    init(
        previousData: Data, previousIndex: CollectionDataIndex<ID>, currentIndex: CollectionDataIndex<ID>,
        lookup: inout [ID: Int]?, hasDeletions: Bool
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
