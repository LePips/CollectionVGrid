/// A view of base identities and their repetitions, without copying repeated items.
struct CollectionSnapshot<ID: Hashable> {

    let ids: [ID]
    let count: Int

    private let positions: [Int]?

    var isUnfiltered: Bool {
        positions == nil
    }

    init(ids: [ID], count: Int? = nil) {
        let count = count ?? ids.count
        precondition(count >= 0 && (count == 0 || !ids.isEmpty))

        self.ids = ids
        self.count = count
        positions = nil
    }

    /// Deleted-stage positions refer to the original, unfiltered source snapshot.
    init(source: Self, positions: [Int]) {
        precondition(source.positions == nil)

        ids = source.ids
        count = positions.count
        self.positions = positions
    }
}

extension CollectionSnapshot: RandomAccessCollection {

    typealias Index = Int

    var startIndex: Int {
        0
    }

    var endIndex: Int {
        count
    }

    subscript(position: Int) -> CollectionItem<ID> {
        precondition(indices.contains(position))

        let sourcePosition = positions?[position] ?? position
        return CollectionItem(id: ids[sourcePosition % ids.count], repetition: sourcePosition / ids.count)
    }
}
