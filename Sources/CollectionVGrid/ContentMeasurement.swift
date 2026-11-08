import SwiftUI

/// Read the SwiftUI layout result before a hosting view rounds it to physical pixels.
/// Keep fractional dimensions accurate as the collection's width changes.
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

/// Measures item content with one retained hosting view. Building a hosting
/// hierarchy costs far more than laying out an existing one, so each additional
/// width during a resize only updates the proposal. Owners discard the measurer
/// whenever measurements are invalidated, so changed content, revisions, and
/// traits are measured from a new hierarchy, as they were before.
@MainActor
final class ContentMeasurer<Content: View> {
    private struct Root: View {
        let content: Content
        let identity: AnyHashable
        let width: CGFloat?
        let environment: EnvironmentValues?
        let measurement: ContentMeasurement

        var body: some View {
            // Like a reused cell, a different element starts with fresh state.
            ContentMeasurementLayout(width: width, measurement: measurement) {
                EnvironmentAwareContent(content: content, environment: environment)
                    .frame(width: width)
                    .id(identity)
            }
        }
    }

    private let measurement = ContentMeasurement()
    #if canImport(UIKit)
    private var host: UIHostingController<Root>?
    #else
    private var host: NSHostingView<Root>?
    #endif

    func size(of content: Content, identity: AnyHashable, width: CGFloat?, environment: EnvironmentValues? = nil) -> CGSize {
        let root = Root(content: content, identity: identity, width: width, environment: environment, measurement: measurement)
        #if canImport(UIKit)
        if let host {
            host.rootView = root
            _ = host.sizeThatFits(in: .zero)
        } else {
            let host = UIHostingController(rootView: root)
            host.safeAreaRegions.remove(.container)
            _ = host.sizeThatFits(in: .zero)
            self.host = host
        }
        #else
        if let host {
            host.rootView = root
        } else {
            host = NSHostingView(rootView: root)
        }
        _ = host?.fittingSize
        #endif
        return CGSize(width: nonnegativeFinite(measurement.size.width), height: nonnegativeFinite(measurement.size.height))
    }
}
