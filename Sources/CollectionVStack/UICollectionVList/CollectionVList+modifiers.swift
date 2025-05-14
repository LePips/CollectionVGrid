import SwiftUI

#if !os(tvOS)
extension CollectionVList {
    
    public func onRowDelete(title: String = "Delete", perform action: @escaping (Element) -> Void) -> Self {
        copy(modifying: \.deleteActionProvider, to: { e, _ in action(e) })
            .copy(modifying: \.deleteActionTitle, to: title)
    }
    
    public func onRowDelete(title: String = "Delete", perform action: @escaping (Element, CollectionVGridLocation) -> Void) -> Self {
        copy(modifying: \.deleteActionProvider, to: action)
            .copy(modifying: \.deleteActionTitle, to: title)
    }
}
#endif
