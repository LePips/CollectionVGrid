import SwiftUI

public extension CollectionVGrid {

    func onReachedBottomEdge(
        offset: CollectionVGridEdgeOffset = .offset(0),
        action: @escaping () -> Void
    ) -> Self {
        copy(modifying: \.onReachedBottomEdge, to: action)
            .copy(modifying: \.onReachedBottomEdgeOffset, to: offset)
    }

    func onReachedTopEdge(
        offset: CollectionVGridEdgeOffset = .offset(0),
        action: @escaping () -> Void
    ) -> Self {
        copy(modifying: \.onReachedTopEdge, to: action)
            .copy(modifying: \.onReachedTopEdgeOffset, to: offset)
    }

    func onPrefetchingElements(_ action: @escaping ([Element]) -> Void) -> Self {
        copy(modifying: \.onPrefetchingElements, to: action)
    }

    func onCancelPrefetchingElements(_ action: @escaping ([Element]) -> Void) -> Self {
        copy(modifying: \.onCancelPrefetchingElements, to: action)
    }

    func header<NewHeader: View>(@ViewBuilder _ headerProvider: @escaping () -> NewHeader) -> CollectionVGrid<Element, Data, ID, Content, NewHeader> {
        CollectionVGrid<Element, Data, ID, Content, NewHeader>(
            id: _id,
            data: data,
            layout: layout,
            onReachedBottomEdge: onReachedBottomEdge,
            onReachedBottomEdgeOffset: onReachedBottomEdgeOffset,
            onReachedTopEdge: onReachedTopEdge,
            onReachedTopEdgeOffset: onReachedTopEdgeOffset,
            onPrefetchingElements: onPrefetchingElements,
            onCancelPrefetchingElements: onCancelPrefetchingElements,
            headerProvider: headerProvider,
            viewProvider: viewProvider
        )
    }

    func proxy(_ proxy: CollectionVGridProxy) -> Self {
        copy(modifying: \.proxy, to: proxy)
    }
}
