@testable import CollectionVGrid
import SwiftUI
import Testing

#if os(macOS)
private typealias EnvironmentNativeGrid = NSCollectionVGrid<Int, [Int], Int, EnvironmentPoster>
private typealias EnvironmentPlatformView = NSView
#else
private typealias EnvironmentNativeGrid = UICollectionVGrid<Int, [Int], Int, EnvironmentPoster>
private typealias EnvironmentPlatformView = UIView
#endif

@Suite(.serialized)
@MainActor
struct EnvironmentSizingTests {
    @Test
    func `public grid measures and displays parent typography at every width`() async throws {
        let model = TypographyModel()
        let content = TypographyGrid(model: model)
        #if os(macOS)
        _ = NSApplication.shared
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(CGSize(width: 500, height: 700))
        window.orderBack(nil)
        defer { window.close() }
        #else
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #endif

        var initialGrid: EnvironmentNativeGrid?
        var initialHeight: CGFloat = 0
        for (font, dynamicType) in [(Font.body, DynamicTypeSize.large), (.system(size: 48), .large), (.body, .accessibility3)] {
            model.font = font
            model.dynamicType = dynamicType
            for width: CGFloat in [500, 499.75, 420, 500] {
                #if os(macOS)
                window.setContentSize(CGSize(width: width, height: 700))
                controller.view.layoutSubtreeIfNeeded()
                #else
                window.frame.size.width = width
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                #endif
                try await Task.sleep(for: .milliseconds(80))
                #if os(macOS)
                controller.view.layoutSubtreeIfNeeded()
                #else
                controller.view.layoutIfNeeded()
                #endif
                let grid = try #require(findGrid(controller.view))
                if let initialGrid {
                    #expect(grid === initialGrid)
                } else {
                    initialGrid = grid
                }
                #if os(macOS)
                let availableWidth = grid.scrollView.contentSize.width
                let attributes = try #require(grid.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
                #else
                let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
                let availableWidth = collection.bounds.width
                let attributes = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
                #endif
                let size = grid.computeItemSize(forWidth: availableWidth).itemSize
                let reference = EnvironmentPoster(model: nil)
                    .font(font)
                    .dynamicTypeSize(dynamicType)
                    .frame(width: size.width)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(macOS)
                let referenceHost = NSHostingController(rootView: reference)
                #else
                let referenceHost = UIHostingController(rootView: reference)
                #endif
                let expected = referenceHost.sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude))
                #expect(abs(size.height - expected.height) < 1)
                #expect(abs(attributes.frame.height - expected.height) < 1)
                #expect(model.displayedFont == font)
                #expect(model.displayedDynamicType == dynamicType)
                if initialHeight == 0 {
                    initialHeight = size.height
                }
                if font == .system(size: 48), width == 500 {
                    #expect(size.height > initialHeight + 10)
                }
            }
        }
    }

    private func findGrid(_ view: EnvironmentPlatformView) -> EnvironmentNativeGrid? {
        if let grid = view as? EnvironmentNativeGrid {
            return grid
        }
        return view.subviews.lazy.compactMap(findGrid).first
    }
}

@MainActor
private final class TypographyModel: ObservableObject {
    @Published
    var font = Font.body
    @Published
    var dynamicType = DynamicTypeSize.large
    var displayedFont: Font?
    var displayedDynamicType: DynamicTypeSize?
}

private struct TypographyGrid: View {
    @ObservedObject
    var model: TypographyModel

    var body: some View {
        CollectionVGrid(count: 24, layout: .columns(2, insets: .init(), itemSpacing: 10)) { _ in
            EnvironmentPoster(model: model)
        }
        .font(model.font)
        .dynamicTypeSize(model.dynamicType)
        .ignoresSafeArea()
    }
}

private struct EnvironmentPoster: View {
    @Environment(\.font)
    private var font
    @Environment(\.dynamicTypeSize)
    private var dynamicType
    let model: TypographyModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
            Text("A favorite film worth discovering")
                .lineLimit(2, reservesSpace: true)
        }
        .onChange(of: font, initial: true) { _, value in model?.displayedFont = value }
        .onChange(of: dynamicType, initial: true) { _, value in model?.displayedDynamicType = value }
    }
}
