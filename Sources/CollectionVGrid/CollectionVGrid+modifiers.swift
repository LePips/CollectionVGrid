import Combine
import SwiftUI

public extension CollectionVGrid {

    /// Remeasures items when the publisher emits, updating the cached aspect ratio or height.
    ///
    /// Apply after collection-specific modifiers.
    func remeasureItems<Trigger: Publisher>(on publisher: Trigger) -> some View where Trigger.Failure == Never {
        ItemRemeasurementView(publisher: publisher) { revision in
            copy(modifying: \.itemMeasurementRevision, to: revision)
        }
    }

    #if canImport(UIKit)
    /// Controls UIKit's automatic safe-area adjustment of the grid's scroll insets.
    /// Use `.never` when the supplied layout and header already account for safe areas.
    func contentInsetAdjustmentBehavior(_ behavior: UIScrollView.ContentInsetAdjustmentBehavior) -> Self {
        copy(modifying: \.contentInsetAdjustmentBehavior, to: behavior)
    }
    #endif

    /// Adds a scrolling header. Hidden headers occupy no layout space.
    func header(isVisible: Bool = true, @ViewBuilder _ content: () -> some View) -> Self {
        copy(modifying: \.headerContent, to: isVisible ? AnyView(content()) : nil)
    }

    /// Enables pull-to-refresh on iOS, keeping the indicator visible until the action returns.
    /// Pass `nil` to disable refresh and cancel any running action. Actions should cooperate
    /// with task cancellation. macOS and tvOS do not display a pull-to-refresh control.
    func onRefresh(action: (@MainActor () async -> Void)?) -> Self {
        copy(modifying: \.refreshAction, to: action)
    }

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

    func proxy(_ proxy: CollectionVGridProxy) -> Self {
        copy(modifying: \.proxy, to: proxy)
    }
}
