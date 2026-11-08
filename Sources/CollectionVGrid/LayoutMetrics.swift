import Foundation

extension CollectionVGridLayout {
    /// Resolve columns and width without depending on a native collection layout.
    func itemWidth(for availableWidth: CGFloat) -> (width: CGFloat, columns: Int) {
        guard availableWidth.isFiniteAndPositive else { return (0, 1) }

        let spacing = nonnegativeFinite(itemSpacing)
        let contentWidth = nonnegativeFinite(availableWidth - insets.leading - insets.trailing)
        let value = layoutValue.positiveFinite(or: 1)
        let rawColumns: CGFloat
        switch layoutType {
        case .columns:
            rawColumns = floor(value)
        case .minWidth:
            let estimate = floor((contentWidth + spacing) / (value + spacing))
            // Division can round up just below a column breakpoint (or down at
            // it). Verify neighboring counts against their required geometry,
            // as CollectionHStack does, without a point-sized tolerance.
            rawColumns = [estimate + 1, estimate, estimate - 1].first { columns in
                guard columns.isFinite, columns >= 1 else { return false }

                let occupied = insets.leading + insets.trailing + (columns - 1) * spacing
                return occupied + columns * value <= availableWidth
            } ?? 1
        }
        let columns = Int(rawColumns.clamped(to: 1 ... CGFloat(Int.max).nextDown))
        let width = nonnegativeFinite((contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return (width, columns)
    }

    /// Whether two layouts differ only in their top and bottom insets, which leave
    /// item widths and the content measured at them unchanged.
    func differsOnlyInVerticalInsets(from other: Self) -> Bool {
        layoutType == other.layoutType && layoutValue == other.layoutValue
            && itemSpacing == other.itemSpacing && lineSpacing == other.lineSpacing && itemSizing == other.itemSizing
            && insets.leading == other.insets.leading && insets.trailing == other.insets.trailing
    }
}
