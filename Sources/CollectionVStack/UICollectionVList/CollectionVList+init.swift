import SwiftUI

// MARK: Collection

#if !os(tvOS)
public extension CollectionVList {

    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        @ViewBuilder header: @escaping () -> any View,
        @ViewBuilder content: @escaping (Element) -> Content
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            headerProvider: header,
            viewProvider: { e, _ in content(e) }
        )
    }
}

public extension CollectionVList where Element: Identifiable, ID == Element.ID {

    init(
        uniqueElements: Data,
        @ViewBuilder header: @escaping () -> any View,
        @ViewBuilder content: @escaping (Element) -> Content
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            headerProvider: header,
            viewProvider: { e, _ in content(e) }
        )
    }
}
#endif
