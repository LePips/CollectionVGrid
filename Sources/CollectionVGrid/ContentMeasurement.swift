import SwiftUI

/// Read the SwiftUI layout result before a hosting view rounds it to physical pixels.
/// Caching a rounded ratio causes visible errors to accumulate during window resizing.
final class ContentMeasurement {
    var size: CGSize = .zero
}

struct ContentMeasurementLayout: Layout {
    let width: CGFloat?
    let measurement: ContentMeasurement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
        measurement.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: nil))
    }
}
