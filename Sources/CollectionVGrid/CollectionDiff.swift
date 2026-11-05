/// Structural edits for one section of unique IDs. Inputs have already passed
/// CollectionDataIndex's uniqueness validation; content refresh belongs to the view.
struct CollectionDiff<ID: Hashable> {

    struct Move: Equatable {

        let source: Int
        let target: Int
    }

    struct Stage {

        let data: CollectionSnapshot<ID>
        let deleted: [Int]
        let inserted: [Int]
        let moved: [Move]

        init(
            data: CollectionSnapshot<ID>,
            deleted: [Int] = [],
            inserted: [Int] = [],
            moved: [Move] = []
        ) {
            self.data = data
            self.deleted = deleted
            self.inserted = inserted
            self.moved = moved
        }
    }

    let target: CollectionSnapshot<ID>

    private(set) var deleted: [Int] = []
    private(set) var inserted: [Int] = []
    private(set) var moved: [Move] = []
    private var survivors: CollectionSnapshot<ID>?

    private var hasInsertionsOrMoves: Bool {
        !inserted.isEmpty || !moved.isEmpty
    }

    init(
        source: CollectionSnapshot<ID>,
        target: CollectionSnapshot<ID>,
        lookup: [ID: Int]? = nil
    ) {
        precondition(source.isUnfiltered && target.isUnfiltered, "Diff inputs must use unfiltered identity snapshots")
        self.target = target

        if source.isEmpty {
            inserted = Array(target.indices)
            return
        }

        if target.isEmpty {
            deleted = Array(source.indices)
            return
        }

        if source.ids == target.ids {
            if source.count < target.count {
                inserted = Array(source.count ..< target.count)
            } else if source.count > target.count {
                deleted = Array(target.count ..< source.count)
            }
            return
        }

        // Contiguous insertions/deletions need no matching buffers. Carousel
        // base-count changes cannot use this shortcut because they change strides.
        if source.count == source.ids.count && target.count == target.ids.count {
            let commonCount = Swift.min(source.count, target.count)
            var prefix = 0
            while prefix < commonCount && source.ids[prefix] == target.ids[prefix] {
                prefix += 1
            }

            var suffix = 0
            while suffix < commonCount - prefix
                && source.ids[source.count - suffix - 1] == target.ids[target.count - suffix - 1]
            {
                suffix += 1
            }

            if prefix + suffix == commonCount {
                deleted = Array(prefix ..< source.count - suffix)
                inserted = Array(prefix ..< target.count - suffix)
                return
            }
        }

        // Reuse the lookup built during ID extraction. Hash each source base ID
        // once, then match every repeated identity arithmetically.
        let lookup = lookup ?? CollectionDataIndex.uniqueOffsetLookup(for: target.ids)
        let baseTargets = source.ids.map { lookup[$0] ?? -1 }
        let completeRepetitions = target.count / target.ids.count
        let partialRepetitionCount = target.count % target.ids.count
        var targetReferences = [Int](repeating: -1, count: target.count)
        var survivorCount = 0

        for sourcePosition in source.indices {
            let baseTarget = baseTargets[sourcePosition % source.ids.count]
            let repetition = sourcePosition / source.ids.count
            let fitsTarget = repetition < completeRepetitions
                || (repetition == completeRepetitions && baseTarget < partialRepetitionCount)

            if baseTarget >= 0 && fitsTarget {
                // fitsTarget bounds the multiplication by target.count.
                let targetPosition = repetition * target.ids.count + baseTarget
                targetReferences[targetPosition] = survivorCount
                survivorCount += 1
            } else {
                deleted.append(sourcePosition)
            }
        }

        var lastSurvivor = -1
        var reordered = false
        for position in targetReferences.indices {
            let survivor = targetReferences[position]
            if survivor < 0 {
                inserted.append(position)
            } else {
                if survivor < lastSurvivor {
                    reordered = true
                }
                lastSurvivor = survivor
            }
        }

        if reordered {
            moved = Self.moves(in: targetReferences, survivorCount: survivorCount)
        }

        if !deleted.isEmpty && hasInsertionsOrMoves {
            // Only a mixed deletion/insertion-or-move needs an intermediate
            // position map. Pure reorders keep just integer match references.
            var survivorPositions: [Int] = []
            survivorPositions.reserveCapacity(survivorCount)
            var nextPosition = source.startIndex

            for deletedPosition in deleted {
                if nextPosition < deletedPosition {
                    survivorPositions.append(contentsOf: nextPosition ..< deletedPosition)
                }
                nextPosition = deletedPosition + 1
            }
            survivorPositions.append(contentsOf: nextPosition ..< source.endIndex)

            survivors = CollectionSnapshot(source: source, positions: survivorPositions)
        }
    }

    private static func moves(in references: [Int], survivorCount: Int) -> [Move] {
        var visited = [Bool](repeating: false, count: survivorCount)
        var cursor = 0
        var singleMove: Move?

        for position in references.indices {
            let survivor = references[position]
            guard survivor >= 0 else { continue }

            while cursor < visited.count && visited[cursor] {
                cursor += 1
            }

            if survivor != cursor {
                // One greedy move is already optimal. As soon as a second is
                // required, switch to LIS instead of materializing a large plan.
                if singleMove != nil {
                    return minimumMoves(in: references)
                }
                singleMove = Move(source: survivor, target: position)
            }
            visited[survivor] = true
        }

        return singleMove.map { [$0] } ?? []
    }

    private static func minimumMoves(in references: [Int]) -> [Move] {
        var tails: [Int] = []
        var predecessors = [Int](repeating: -1, count: references.count)

        for position in references.indices where references[position] >= 0 {
            let survivor = references[position]
            var lower = 0
            var upper = tails.count

            while lower < upper {
                let middle = (lower + upper) / 2
                if references[tails[middle]] < survivor {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }

            if lower > 0 {
                predecessors[position] = tails[lower - 1]
            }
            if lower == tails.count {
                tails.append(position)
            } else {
                tails[lower] = position
            }
        }

        var stationary = [Bool](repeating: false, count: references.count)
        var position = tails.last ?? -1
        while position >= 0 {
            stationary[position] = true
            position = predecessors[position]
        }

        var moves: [Move] = []
        for position in references.indices where references[position] >= 0 && !stationary[position] {
            moves.append(Move(source: references[position], target: position))
        }
        return moves
    }
}

extension CollectionDiff: RandomAccessCollection {

    typealias Index = Int

    var startIndex: Int {
        0
    }

    var endIndex: Int {
        (deleted.isEmpty ? 0 : 1) + (hasInsertionsOrMoves ? 1 : 0)
    }

    subscript(position: Int) -> Stage {
        precondition(indices.contains(position))

        if position == 0 && !deleted.isEmpty {
            return Stage(data: survivors ?? target, deleted: deleted)
        }
        return Stage(data: target, inserted: inserted, moved: moved)
    }
}
