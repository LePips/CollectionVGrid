import Foundation

/// Reuses the first valid content proportion or height across resizes, without pixel rounding.
struct ItemSizeCache {
    private var cachedValue: (sizing: CollectionVGridLayout.ItemSizing, value: CGFloat)?

    mutating func size(
        width: CGFloat,
        sizing: CollectionVGridLayout.ItemSizing = .aspectRatio,
        measure: () -> CGSize
    ) -> CGSize {
        guard width.isFiniteAndPositive else { return .zero }

        let value: CGFloat
        if let cachedValue, cachedValue.sizing == sizing {
            value = cachedValue.value
        } else {
            cachedValue = nil
            let measured = measure()
            value = switch sizing {
            case .aspectRatio: measured.width / measured.height
            case .height: measured.height
            }
            guard value.isFiniteAndPositive else {
                return CGSize(width: width, height: nonnegativeFinite(measured.height))
            }
            cachedValue = (sizing, value)
        }

        let height = switch sizing {
        case .aspectRatio: width / value
        case .height: value
        }
        return CGSize(width: width, height: nonnegativeFinite(height))
    }
}
