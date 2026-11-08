import Foundation

/// Caches content measurements by width, or an explicitly requested proportion/height.
struct ItemSizeCache {
    private var widthSizes: [CGSize] = []
    private var cachedValue: (sizing: CollectionVGridLayout.ItemSizing, value: CGFloat)?

    mutating func size(
        width: CGFloat,
        sizing: CollectionVGridLayout.ItemSizing = .content,
        measure: () -> CGSize
    ) -> CGSize {
        guard width.isFiniteAndPositive else { return .zero }

        if sizing == .content {
            cachedValue = nil
            if let index = widthSizes.firstIndex(where: { $0.width == width }) {
                let size = widthSizes.remove(at: index)
                widthSizes.append(size)
                return size
            }
            let measured = measure()
            let size = CGSize(width: width, height: nonnegativeFinite(measured.height))
            if measured.width.isFiniteAndPositive, measured.height.isFiniteAndPositive {
                // SwiftUI can alternate proposals during a resize. Bound the cache
                // so live resizing does not retain every intermediate width.
                if widthSizes.count == 8 {
                    widthSizes.removeFirst()
                }
                widthSizes.append(size)
            }
            return size
        }
        widthSizes.removeAll(keepingCapacity: true)

        let value: CGFloat
        if let cachedValue, cachedValue.sizing == sizing {
            value = cachedValue.value
        } else {
            cachedValue = nil
            let measured = measure()
            value = switch sizing {
            case .aspectRatio: measured.width / measured.height
            case .height, .content: measured.height
            }
            guard value.isFiniteAndPositive else {
                return CGSize(width: width, height: nonnegativeFinite(measured.height))
            }

            cachedValue = (sizing, value)
        }

        let height = switch sizing {
        case .aspectRatio: width / value
        case .height, .content: value
        }
        return CGSize(width: width, height: nonnegativeFinite(height))
    }
}
