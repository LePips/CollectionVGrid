#if canImport(CollectionHStack)
@testable import CollectionHStack
#else
@testable import CollectionVGrid
#endif
import Testing

struct CollectionDiffTests {

    @Test
    func `exhaustive ordered subsets`() throws {
        let inputs = permutations(of: Array(0 ..< 4))

        for source in inputs {
            for target in inputs {
                try validate(source: CollectionSnapshot(ids: source), target: CollectionSnapshot(ids: target))
            }
        }

        #expect(inputs.count == 65)
    }

    @Test
    func `mixed edits and partial repetitions`() throws {
        var random = DiffRandom(state: 0xDEAD_BEEF)
        let universe = Array(0 ..< 30)

        for iteration in 0 ..< 1000 {
            let sourceIDs = Array(universe.shuffled(using: &random).prefix(Int.random(in: 0 ... 30, using: &random)))
            let targetIDs = Array(universe.shuffled(using: &random).prefix(Int.random(in: 0 ... 30, using: &random)))
            let sourceCount = sourceIDs.isEmpty ? 0 : Int.random(in: sourceIDs.count ... 150, using: &random)
            let targetCount = targetIDs.isEmpty ? 0 : Int.random(in: targetIDs.count ... 150, using: &random)

            try validate(
                source: CollectionSnapshot(ids: sourceIDs, count: sourceCount),
                target: CollectionSnapshot(ids: targetIDs, count: targetCount)
            )

            if iteration.isMultiple(of: 10) {
                try validate(
                    source: CollectionSnapshot(ids: sourceIDs.map(DiffCollidingID.init), count: sourceCount),
                    target: CollectionSnapshot(ids: targetIDs.map(DiffCollidingID.init), count: targetCount)
                )
            }
        }
    }

    @Test
    func `rotations use one move in either direction`() throws {
        let source = CollectionSnapshot(ids: Array(0 ..< 1000))
        let left = CollectionSnapshot(ids: Array(1 ..< 1000) + [0])
        let right = CollectionSnapshot(ids: [999] + Array(0 ..< 999))

        let leftChanges = CollectionDiff(source: source, target: left)
        let rightChanges = CollectionDiff(source: source, target: right)

        #expect(leftChanges.moved == [.init(source: 0, target: 999)])
        #expect(rightChanges.moved == [.init(source: 999, target: 0)])
        try validate(source: source, target: left)
        try validate(source: source, target: right)
    }

    @Test
    func `contiguous edits and carousel count changes`() throws {
        for size in [1, 2, 7, 99, 100, 101] {
            let ids = Array(0 ..< size)
            let ordinary = CollectionSnapshot(ids: ids)
            let repeated = CollectionSnapshot(ids: ids, count: max(100, size))
            let retained = CollectionSnapshot(ids: ids, count: max(100, size * 10))
            let targets = [
                CollectionSnapshot(ids: ids + [size]),
                CollectionSnapshot(ids: [size] + ids),
                CollectionSnapshot(ids: Array(ids.dropFirst())),
                CollectionSnapshot(ids: Array(ids.dropLast())),
                CollectionSnapshot(ids: Array(ids.reversed())),
                CollectionSnapshot(ids: [Int]()),
            ]

            for target in targets {
                try validate(source: ordinary, target: target)
            }

            try validate(source: ordinary, target: repeated)
            try validate(source: repeated, target: ordinary)
            try validate(source: retained, target: CollectionSnapshot(ids: ids + [size], count: retained.count))
            try validate(source: retained, target: CollectionSnapshot(ids: [0], count: retained.count))
            try validate(source: ordinary, target: ordinary)
        }
    }

    @Test
    func `repeated matching hashes only base IDs`() {
        let hashes = DiffHashCounter()
        let ids = (0 ..< 4).map { DiffCountedID(value: $0, hashes: hashes) }
        let source = CollectionSnapshot(ids: Array(ids.prefix(3)), count: 10000)
        let target = CollectionSnapshot(ids: ids, count: 10000)
        let lookup = CollectionDataIndex.uniqueOffsetLookup(for: target.ids)
        hashes.count = 0

        let changes = CollectionDiff(source: source, target: target, lookup: lookup)

        #expect(hashes.count == 3)
        #expect(changes.count == 2)
        #expect(changes.moved.isEmpty)
        #expect(changes.last?.data.count == 10000)
    }

    @Test
    func `nil identities and shifted slices`() throws {
        let previousData: [Int?] = [9, nil, 1, 2]
        let nextData: [Int?] = [2, nil, 3]
        var previous = CollectionDataIndex<Int?>()
        previous.update(from: previousData[1...], id: \.self, prefix: nil)
        var current = previous
        current.update(from: nextData[...], id: \.self, prefix: nil)

        try validate(source: previous.items(count: 100), target: current.items(count: 101))
    }

    private func permutations(of available: [Int]) -> [[Int]] {
        [[]] + available.flatMap { first in
            permutations(of: available.filter { $0 != first }).map { [first] + $0 }
        }
    }

    private func validate<ID: Hashable>(source: CollectionSnapshot<ID>, target: CollectionSnapshot<ID>) throws {
        let sourceIDs = source.map(\.identity)
        let targetIDs = target.map(\.identity)
        let oldSet = Set(sourceIDs)
        let newSet = Set(targetIDs)
        let lookup = CollectionDataIndex.uniqueOffsetLookup(for: target.ids)

        let changes = CollectionDiff(source: source, target: target, lookup: lookup)
        var state = sourceIDs
        for stage in changes {
            state = try replay(source: state, stage: stage)
        }

        #expect(changes.deleted.count == oldSet.subtracting(newSet).count)
        #expect(changes.inserted.count == newSet.subtracting(oldSet).count)
        #expect(state == targetIDs)
        #expect(Set(state).count == state.count)

        // An independent quadratic LCS checks optimality on the small corpus.
        // Large cases exercise replay without making the test itself quadratic.
        if max(source.count, target.count) <= 150 {
            #expect(changes.moved.count == oldSet.intersection(newSet).count - commonSubsequence(sourceIDs, targetIDs))
        }
    }

    private func replay<ID: Hashable>(
        source: [CollectionItem<ID>.Identity],
        stage: CollectionDiff<ID>.Stage
    ) throws -> [CollectionItem<ID>.Identity] {
        let target = stage.data.map(\.identity)
        let deleted = Set(stage.deleted)
        let movedSources = Set(stage.moved.map(\.source))
        let destinations = stage.inserted + stage.moved.map(\.target)

        try #require(deleted.count == stage.deleted.count)
        try #require(movedSources.count == stage.moved.count)
        try #require(deleted.isDisjoint(with: movedSources))
        try #require(Set(destinations).count == destinations.count)
        try #require((stage.deleted + stage.moved.map(\.source)).allSatisfy { source.indices.contains($0) })
        try #require(destinations.allSatisfy { target.indices.contains($0) })
        try #require(source.count - stage.deleted.count + stage.inserted.count == target.count)

        var result = [CollectionItem<ID>.Identity?](repeating: nil, count: target.count)
        for position in stage.inserted {
            result[position] = target[position]
        }
        for move in stage.moved {
            result[move.target] = source[move.source]
        }

        var remaining = source.indices.filter { !deleted.contains($0) && !movedSources.contains($0) }.makeIterator()
        for position in result.indices where result[position] == nil {
            let next = remaining.next()
            let sourcePosition = try #require(next)
            result[position] = source[sourcePosition]
        }

        let remainingPosition = remaining.next()
        #expect(remainingPosition == nil)
        #expect(result.compactMap(\.self) == target)
        #expect(Set(target).count == target.count)
        return result.compactMap(\.self)
    }

    private func commonSubsequence<Value: Equatable>(_ source: [Value], _ target: [Value]) -> Int {
        var lengths = [Int](repeating: 0, count: target.count + 1)

        for value in source {
            var diagonal = 0
            for position in target.indices {
                let previous = lengths[position + 1]
                lengths[position + 1] = value == target[position]
                    ? diagonal + 1
                    : max(lengths[position], lengths[position + 1])
                diagonal = previous
            }
        }

        return lengths[target.count]
    }
}

private struct DiffRandom {

    var state: UInt64
}

extension DiffRandom: RandomNumberGenerator {

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private struct DiffCollidingID {

    let value: Int
}

extension DiffCollidingID: Hashable {

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

private final class DiffHashCounter {

    var count = 0
}

private struct DiffCountedID {

    let value: Int
    let hashes: DiffHashCounter
}

extension DiffCountedID: Hashable {

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hashes.count += 1
        hasher.combine(value)
    }
}
