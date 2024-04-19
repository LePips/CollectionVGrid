import OrderedCollections
import SwiftUI

public struct CollectionVGrid<Element: Hashable>: UIViewRepresentable {

    public typealias UIViewType = UICollectionVGrid<Element>

    var data: Binding<OrderedSet<Element>>
    var layout: Binding<CollectionVGridLayout>
    var onReachedBottomEdge: () -> Void
    var onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    var onReachedTopEdge: () -> Void
    var onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    var proxy: CollectionVGridProxy<Element>?
    let viewProvider: (Element, CollectionVGridLocation) -> any View

    init(
        data: Binding<OrderedSet<Element>>,
        layout: Binding<CollectionVGridLayout>,
        onReachedBottomEdge: @escaping () -> Void = {},
        onReachedBottomEdgeOffset: CollectionVGridEdgeOffset = .offset(0),
        onReachedTopEdge: @escaping () -> Void = {},
        onReachedTopEdgeOffset: CollectionVGridEdgeOffset = .offset(0),
        @ViewBuilder viewProvider: @escaping (Element, CollectionVGridLocation) -> any View
    ) {
        self.data = data
        self.layout = layout
        self.onReachedBottomEdge = onReachedBottomEdge
        self.onReachedBottomEdgeOffset = onReachedBottomEdgeOffset
        self.onReachedTopEdge = onReachedTopEdge
        self.onReachedTopEdgeOffset = onReachedTopEdgeOffset
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIViewType {
        UICollectionVGrid(
            data: data,
            layout: layout,
            onReachedBottomEdge: onReachedBottomEdge,
            onReachedBottomEdgeOffset: onReachedBottomEdgeOffset,
            onReachedTopEdge: onReachedTopEdge,
            onReachedTopEdgeOffset: onReachedTopEdgeOffset,
            proxy: proxy,
            viewProvider: viewProvider
        )
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(
            with: data,
            layout: layout
        )
    }
}
