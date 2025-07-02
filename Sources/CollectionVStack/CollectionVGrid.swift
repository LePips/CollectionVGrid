import DifferenceKit
import SwiftUI

public struct CollectionVGrid<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>: UIViewRepresentable where Data.Element == Element,
Data.Index == Int {

    public typealias UIViewType = UICollectionVGrid<Element, Data, ID, Content>

    let _id: KeyPath<Element, ID>
    let data: Data
    let layout: CollectionVGridLayout
    var onReachedBottomEdge: () -> Void
    var onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    var onReachedTopEdge: () -> Void
    var onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    var onPrefetchingElements: ([Element]) -> Void
    var onCancelPrefetchingElements: ([Element]) -> Void
    var proxy: CollectionVGridProxy?
    let viewProvider: (Element, CollectionVGridLocation) -> Content

    init(
        id: KeyPath<Element, ID>,
        data: Data,
        layout: CollectionVGridLayout,
        onReachedBottomEdge: @escaping () -> Void = {},
        onReachedBottomEdgeOffset: CollectionVGridEdgeOffset = .offset(0),
        onReachedTopEdge: @escaping () -> Void = {},
        onReachedTopEdgeOffset: CollectionVGridEdgeOffset = .offset(0),
        onPrefetchingElements: @escaping ([Element]) -> Void = { _ in },
        onCancelPrefetchingElements: @escaping ([Element]) -> Void = { _ in },
        @ViewBuilder viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self._id = id
        self.data = data
        self.layout = layout
        self.onReachedBottomEdge = onReachedBottomEdge
        self.onReachedBottomEdgeOffset = onReachedBottomEdgeOffset
        self.onReachedTopEdge = onReachedTopEdge
        self.onReachedTopEdgeOffset = onReachedTopEdgeOffset
        self.onPrefetchingElements = onPrefetchingElements
        self.onCancelPrefetchingElements = onCancelPrefetchingElements
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIViewType {
        UICollectionVGrid(
            id: _id,
            data: data,
            layout: layout,
            onReachedBottomEdge: onReachedBottomEdge,
            onReachedBottomEdgeOffset: onReachedBottomEdgeOffset,
            onReachedTopEdge: onReachedTopEdge,
            onReachedTopEdgeOffset: onReachedTopEdgeOffset,
            onPrefetchingElements: onPrefetchingElements,
            onCancelPrefetchingElements: onCancelPrefetchingElements,
            proxy: proxy,
            viewProvider: viewProvider
        )
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(
            data: data,
            layout: layout,
            isScrollEnabled: context.environment.isScrollEnabled,
            verticalScrollIndicatorVisibility: context.environment.verticalScrollIndicatorVisibility
        )
    }
}
