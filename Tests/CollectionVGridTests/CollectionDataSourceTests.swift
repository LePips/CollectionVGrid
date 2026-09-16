#if canImport(CollectionHStack)
@testable import CollectionHStack
#else
@testable import CollectionVGrid
#endif
import DifferenceKit
import Testing

struct CollectionDataSourceTests {
    private struct Value {
        let id: Int
        let content: String
    }

    @Test
    func eachDiffStageResolvesLatestSurvivorsAndRemovedSourceElements() {
        let old = (0 ..< 7).map { Value(id: $0, content: "old") }[2 ..< 6]
        let next = [Value(id: 5, content: "new"), Value(id: 3, content: "new"), Value(id: 7, content: "inserted")][...]
        var previous = CollectionDataIndex<Int>()
        previous.update(from: old, id: \.id, prefix: nil)
        var current = previous
        var lookup: [Int: Int]?
        current.update(from: next, id: \.id, prefix: nil, lookup: &lookup)
        let source = previous.items(count: 12)
        let changes = StagedChangeset(source: source, target: current.items(count: 12), section: 0)
        let transition = CollectionDataTransition(
            previousData: old, previousIndex: previous, currentIndex: current, lookup: &lookup,
            hasDeletions: changes.contains { !$0.elementDeleted.isEmpty }
        )
        #expect(lookup == nil)
        #expect(!changes.isEmpty)
        for items in [source] + changes.map(\.data) {
            for item in items {
                let element = transition.element(for: item.id, in: next, index: current)
                #expect(element.id == item.id)
                let expected = next.first { $0.id == item.id } ?? old.first { $0.id == item.id }
                #expect(element.content == expected?.content)
            }
        }
    }

    @Test
    func repeatedItemsAndGrowthNeedOnlyIdentityMetadata() {
        var index = CollectionDataIndex<Int>()
        index.update(from: [10, 20, 30][1...], id: \.self, prefix: nil)
        let items = index.items(count: 105)
        #expect(items.count == 105)
        #expect(items[104].id == 20)
        #expect(items[104].repetition == 52)
        #expect(Set(items.map(\.differenceIdentifier)).count == 105)
        var lookup: [Int: Int]?
        let transition = CollectionDataTransition(
            previousData: [10, 20, 30][1...], previousIndex: index, currentIndex: index,
            lookup: &lookup, hasDeletions: false
        )
        #expect(transition.element(for: 30, in: [10, 20, 30][1...], index: index) == 30)
        #expect(CollectionDataIndex<Int>().items().isEmpty)
    }

    @Test
    func transitionReleasesRemovedElementsWhenTheDiffFinishes() {
        final class Element { let id = 1 }
        weak var removed: Element?
        var transition: CollectionDataTransition<[Element], Int>?
        let current = CollectionDataIndex<Int>()
        do {
            let element = Element()
            removed = element
            var previous = CollectionDataIndex<Int>()
            previous.update(from: [element], id: \.id, prefix: nil)
            var lookup: [Int: Int]?
            transition = CollectionDataTransition(
                previousData: [element], previousIndex: previous, currentIndex: current,
                lookup: &lookup, hasDeletions: true
            )
        }
        #expect(removed != nil)
        #expect(transition?.element(for: 1, in: [], index: current) === removed)
        transition = nil
        #expect(removed == nil)
    }
}
