import SwiftUI

// MARK: Collection

public extension CollectionVGrid {

    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        layout: CollectionVGridLayout,
        @ViewBuilder viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: layout,
            viewProvider: viewProvider
        )
    }

    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        layout: CollectionVGridLayout,
        @ViewBuilder viewProvider: @escaping (Element) -> Content
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: layout,
            viewProvider: { e, _ in viewProvider(e) }
        )
    }
}

public extension CollectionVGrid where Element: Identifiable, ID == Element.ID {

    init(
        uniqueElements: Data,
        layout: CollectionVGridLayout,
        @ViewBuilder viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: layout,
            viewProvider: viewProvider
        )
    }

    init(
        uniqueElements: Data,
        layout: CollectionVGridLayout,
        @ViewBuilder viewProvider: @escaping (Element) -> Content
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: layout,
            viewProvider: { e, _ in viewProvider(e) }
        )
    }
}

// MARK: Count

public extension CollectionVGrid where Data == [Element], Element == Int, ID == Int {

    init(
        count: Int,
        layout: CollectionVGridLayout,
        @ViewBuilder viewProvider: @escaping (Element) -> Content
    ) {
        self.init(
            id: \.self,
            data: Array(0 ..< count),
            layout: layout,
            viewProvider: { e, _ in viewProvider(e) }
        )
    }
}
