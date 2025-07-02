import SwiftUI

#if !os(tvOS)
/// - Important: Currently experimental.
public struct CollectionVList<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>: UIViewRepresentable where Data.Element == Element,
Data.Index == Int {

    public typealias UIViewType = UICollectionVList<Element, Data, ID, Content>

    let _id: KeyPath<Element, ID>
    let data: Data
    var deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?
    var deleteActionTitle: String
    var headerProvider: () -> any View
    var viewProvider: (Element, CollectionVGridLocation) -> Content

    init(
        id: KeyPath<Element, ID>,
        data: Data,
        deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)? = nil,
        deleteActionTitle: String = "Delete",
        headerProvider: @escaping () -> any View,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self._id = id
        self.data = data
        self.deleteActionProvider = deleteActionProvider
        self.deleteActionTitle = deleteActionTitle
        self.headerProvider = headerProvider
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIViewType {
        UICollectionVList(
            id: _id,
            data: data,
            deleteActionProvider: deleteActionProvider,
            deleteActionTitle: deleteActionTitle,
            headerProvider: headerProvider,
            viewProvider: viewProvider
        )
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(
            data: data,
            isScrollEnabled: context.environment.isScrollEnabled,
            verticalScrollIndicatorVisibility: context.environment.verticalScrollIndicatorVisibility
        )
    }
}
#endif
