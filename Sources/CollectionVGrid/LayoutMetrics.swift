import Foundation

extension CollectionVGridLayout {
    /// Resolve columns and width without depending on a native collection layout.
    func itemWidth(for availableWidth: CGFloat) -> (width: CGFloat, columns: Int) {
        guard availableWidth.isFiniteAndPositive else { return (0, 1) }
        let spacing = nonnegativeFinite(itemSpacing)
        let contentWidth = nonnegativeFinite(availableWidth - insets.leading - insets.trailing)
        let value = layoutValue.positiveFinite(or: 1)
        let rawColumns: CGFloat = switch layoutType {
        case .columns: floor(value)
        case .minWidth: floor((contentWidth + spacing) / (value + spacing))
        }
        let columns = Int(rawColumns.clamped(to: 1 ... CGFloat(Int.max).nextDown))
        let width = nonnegativeFinite((contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return (width, columns)
    }
}
