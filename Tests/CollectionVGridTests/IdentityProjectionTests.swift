@testable import CollectionVGrid
import SwiftUI
import Testing

struct IdentityProjectionTests {
    @Test
    func `direct projection reads every identity including mutations in retained references`() {
        final class Item {
            var id: Int
            init(_ id: Int) {
                self.id = id
            }
        }
        let data = [Item(10), Item(20), Item(30)]
        var reads = 0
        func identifier(_ item: Item) -> Int {
            reads += 1
            return item.id
        }
        var index = CollectionDataIndex<Int>()
        var lookup: [Int: Int]?
        #expect(index.update(from: data, identifier: identifier, prefix: nil, lookup: &lookup))
        #expect(reads == 3)
        reads = 0
        #expect(!index.update(from: data, identifier: identifier, prefix: nil, lookup: &lookup))
        #expect(reads == 3)
        #expect(lookup == nil)

        // Same array buffer, different current identity: never skip the scan
        // based on collection storage or object identity.
        data[1].id = 40
        reads = 0
        #expect(index.update(from: data, identifier: identifier, prefix: nil, lookup: &lookup))
        #expect(reads == 3)
        #expect(index.ids == [10, 40, 30])
        #expect(lookup == [10: 0, 40: 1, 30: 2])
    }

    @Test
    func `projection respects slices prefixes and current computed identities`() {
        let data = Array(0 ..< 10)[3 ..< 8]
        var revision = 0
        var index = CollectionDataIndex<Int>()
        var lookup: [Int: Int]?
        #expect(index.update(from: data, identifier: { $0 + revision }, prefix: 2, lookup: &lookup))
        #expect(index.ids == [3, 4])
        #expect(index.makeLookup() == [3: 3, 4: 4])
        revision = 10
        #expect(index.update(from: data, identifier: { $0 + revision }, prefix: 2, lookup: &lookup))
        #expect(index.ids == [13, 14])
        #expect(index.element(in: data, at: 1) == 4)
    }

    @Test
    func `retained lookup follows shifted slices with unchanged projected identities`() {
        struct Item {
            let id: Int
        }
        var index = CollectionDataIndex<Int>()
        var lookup: [Int: Int] = [:]
        let initial = [Item(id: 99), Item(id: 10), Item(id: 20)][1...]
        #expect(index.update(from: initial, identifier: { $0.id }, prefix: nil, retainingLookup: &lookup))
        #expect(lookup == [10: 1, 20: 2])
        let shifted = [Item(id: 0), Item(id: 99), Item(id: 10), Item(id: 20)][2...]
        #expect(!index.update(from: shifted, identifier: { $0.id }, prefix: nil, retainingLookup: &lookup))
        #expect(lookup == [10: 2, 20: 3])
        #expect(index.element(in: shifted, at: 1).id == 20)
    }

    @MainActor
    @Test
    func `Identifiable and explicit key paths retain their distinct identity semantics`() {
        struct Item: Identifiable {
            let id: Int
            let alternateID: Int
        }
        let item = Item(id: 1, alternateID: 2)
        let automatic = CollectionVGrid(uniqueElements: [item], layout: .columns(1)) { _ in Color.blue }
        let automaticLocation = CollectionVGrid(uniqueElements: [item], layout: .columns(1)) { _, _ in Color.blue }
        let explicit = CollectionVGrid(uniqueElements: [item], id: \.alternateID, layout: .columns(1)) { _ in Color.blue }
        let explicitLocation = CollectionVGrid(uniqueElements: [item], id: \.alternateID, layout: .columns(1)) { _, _ in Color.blue }
        #expect(automatic.identifier(item) == 1)
        #expect(automaticLocation.identifier(item) == 1)
        #expect(explicit.identifier(item) == 2)
        #expect(explicitLocation.identifier(item) == 2)
    }
}
