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

    func proxy(_ proxy: CollectionVGridProxy) -> Self {
        copy(modifying: \.proxy, to: proxy)
    }
}
