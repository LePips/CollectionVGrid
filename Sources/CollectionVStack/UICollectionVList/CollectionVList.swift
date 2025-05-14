import SwiftUI

#if !os(tvOS)
/// - Important: Currently experimental.
public struct CollectionVList<Element, Data: Collection, ID: Hashable>: UIViewRepresentable where Data.Element == Element,
Data.Index == Int {

    public typealias UIViewType = UICollectionVList<Element, Data, ID>

    let _id: KeyPath<Element, ID>
    let data: Data
    var deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?
    var deleteActionTitle: String
    var headerProvider: () -> any View
    var scrollIndicatorsVisible: Bool
    var viewProvider: (Element, CollectionVGridLocation) -> any View
    
    init(
        id: KeyPath<Element, ID>,
        data: Data,
        deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)? = nil,
        deleteActionTitle: String = "Delete",
        headerProvider: @escaping () -> any View,
        scrollIndicatorsVisible: Bool = true,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> any View
    ) {
        self._id = id
        self.data = data
        self.deleteActionProvider = deleteActionProvider
        self.deleteActionTitle = deleteActionTitle
        self.headerProvider = headerProvider
        self.scrollIndicatorsVisible = scrollIndicatorsVisible
        self.viewProvider = viewProvider
    }
    
    public func makeUIView(context: Context) -> UIViewType {
        UICollectionVList(
            id: _id,
            data: data,
            deleteActionProvider: deleteActionProvider,
            deleteActionTitle: deleteActionTitle,
            headerProvider: headerProvider,
            scrollIndicatorsVisible: scrollIndicatorsVisible,
            viewProvider: viewProvider
        )
    }
    
    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(data: data)
    }
}
#endif
