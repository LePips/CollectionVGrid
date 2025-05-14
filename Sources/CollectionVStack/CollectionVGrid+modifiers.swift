public extension CollectionVGrid {

    func onReachedBottomEdge(offset: CollectionVGridEdgeOffset = .offset(0), perform action: @escaping () -> Void) -> Self {
        copy(modifying: \.onReachedBottomEdge, to: action)
            .copy(modifying: \.onReachedBottomEdgeOffset, to: offset)
    }

    func onReachedTopEdge(offset: CollectionVGridEdgeOffset = .offset(0), perform action: @escaping () -> Void) -> Self {
        copy(modifying: \.onReachedTopEdge, to: action)
            .copy(modifying: \.onReachedTopEdgeOffset, to: offset)
    }

    func proxy(_ proxy: CollectionVGridProxy) -> Self {
        copy(modifying: \.proxy, to: proxy)
    }

    func scrollIndicatorsVisible(_ isVisible: Bool = true) -> Self {
        copy(modifying: \.scrollIndicatorsVisible, to: isVisible)
    }
}
