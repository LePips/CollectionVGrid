import SwiftUI

public struct CollectionVGrid<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
> where Data.Element == Element,
Data.Index == Int {

    let _id: KeyPath<Element, ID>
    let data: Data
    let layout: CollectionVGridLayout
    var refreshAction: (@MainActor () async -> Void)?
    var onReachedBottomEdge: () -> Void
    var onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    var onReachedTopEdge: () -> Void
    var onReachedTopEdgeOffset: CollectionVGridEdgeOffset
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
        @ViewBuilder viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self._id = id
        self.data = data
        self.layout = layout
        self.onReachedBottomEdge = onReachedBottomEdge
        self.onReachedBottomEdgeOffset = onReachedBottomEdgeOffset
        self.onReachedTopEdge = onReachedTopEdge
        self.onReachedTopEdgeOffset = onReachedTopEdgeOffset
        self.viewProvider = viewProvider
    }
}

#if canImport(UIKit)
extension CollectionVGrid: UIViewRepresentable {
    public typealias UIViewType = UICollectionVGrid<Element, Data, ID, Content>

    public func makeUIView(context: Context) -> UIViewType {
        let view = UICollectionVGrid(
            id: _id,
            data: data,
            layout: layout,
            onReachedBottomEdge: onReachedBottomEdge,
            onReachedBottomEdgeOffset: onReachedBottomEdgeOffset,
            onReachedTopEdge: onReachedTopEdge,
            onReachedTopEdgeOffset: onReachedTopEdgeOffset,
            proxy: proxy,
            viewProvider: viewProvider
        )
        #if os(iOS)
        view.configureRefresh(action: refreshAction)
        #endif
        return view
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.configure(self)
        view.update(
            data: data,
            layout: layout,
            isScrollEnabled: context.environment.isScrollEnabled,
            verticalScrollIndicatorVisibility: context.environment.verticalScrollIndicatorVisibility,
            viewProvider: viewProvider
        )
    }

    public static func dismantleUIView(_ view: UIViewType, coordinator: ()) {
        #if os(iOS)
        view.configureRefresh(action: nil)
        #endif
    }
}
#endif
