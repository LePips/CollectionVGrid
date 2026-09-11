import Foundation

/// Reuses the first valid content proportion across resizes, without pixel rounding.
struct ItemSizeCache {
    private var aspectRatio: CGFloat?

    mutating func size(width: CGFloat, measure: () -> CGSize) -> CGSize {
        guard width.isFiniteAndPositive else { return .zero }
        if let aspectRatio {
            return CGSize(width: width, height: nonnegativeFinite(width / aspectRatio))
        }
        let measured = measure()
        let ratio = measured.width / measured.height
        if ratio.isFiniteAndPositive {
            aspectRatio = ratio
            return CGSize(width: width, height: nonnegativeFinite(width / ratio))
        }
        return CGSize(width: width, height: nonnegativeFinite(measured.height))
    }
}
