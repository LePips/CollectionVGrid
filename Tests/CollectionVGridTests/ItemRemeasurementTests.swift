@testable import CollectionVGrid
@preconcurrency import Combine
import SwiftUI
import Testing

#if os(macOS)
import AppKit

private typealias NativeGrid = NSCollectionVGrid<Int, [Int], Int, RemeasurementItem>
private typealias PlatformView = NSView
#else
import UIKit

private typealias NativeGrid = UICollectionVGrid<Int, [Int], Int, RemeasurementItem>
private typealias PlatformView = UIView
#endif

@Suite(.serialized)
@MainActor
struct ItemRemeasurementTests {

    @Test(arguments: [CollectionVGridLayout.ItemSizing.aspectRatio, .height])
    func publisherRemeasuresLatestContentAndDerivedSizing(sizing: CollectionVGridLayout.ItemSizing) async throws {
        let model = RemeasurementModel()
        let hosted = RemeasurementHost(model: model, sizing: sizing)
        defer {
            hosted.close()
        }

        await hosted.settle()
        let grid = try #require(findGrid(hosted.view))
        let width = try availableWidth(grid)
        let initial = grid.computeItemSize(forWidth: width).itemSize
        #expect(initial.height == 50)

        // Content changes preserve the cache until a signal.
        model.showsTitle = true
        await hosted.settle()
        #expect(grid.computeItemSize(forWidth: width).itemSize == initial)

        model.primary.send(1)
        model.primary.send(2)
        model.primary.send(3)
        await hosted.settle()
        let expanded = grid.computeItemSize(forWidth: width).itemSize
        #expect(expanded.height > initial.height)
        let resized = grid.computeItemSize(forWidth: width * 2).itemSize
        #expect(abs(resized.height - (sizing == .height ? expanded.height : expanded.height * 2)) < 0.01)
        #expect(try abs(displayedItemSize(grid).height - expanded.height) < 0.01)

        // A signal in the same update must measure the latest content.
        model.showsTitle = false
        model.primary.send(4)
        await hosted.settle()
        #expect(grid.computeItemSize(forWidth: width).itemSize == initial)
        #expect(try abs(displayedItemSize(grid).height - initial.height) < 0.01)

        model.showsTitle = true
        let trigger = model.primary
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                trigger.send(5)
                continuation.resume()
            }
        }
        await hosted.settle()
        #expect(grid.computeItemSize(forWidth: width).itemSize == expanded)
        #expect(findGrid(hosted.view) === grid)
    }

    @Test
    func publisherReplacementAndRemovalFollowViewLifetime() async throws {
        let model = RemeasurementModel()
        let hosted = RemeasurementHost(model: model, sizing: .height)
        defer {
            hosted.close()
        }

        await hosted.settle()
        let grid = try #require(findGrid(hosted.view))
        #expect(model.primarySubscriptions == 1)
        #expect(model.secondarySubscriptions == 0)
        #expect(grid.computeItemSize(forWidth: 300).itemSize.height == 50)

        model.usesSecondary = true
        await hosted.settle()
        #expect(model.primarySubscriptions == 0)
        #expect(model.secondarySubscriptions == 1)

        model.showsTitle = true
        model.primary.send(1)
        await hosted.settle()
        #expect(grid.computeItemSize(forWidth: 300).itemSize.height == 50)

        model.secondary.send(1)
        await hosted.settle()
        #expect(grid.computeItemSize(forWidth: 300).itemSize.height > 50)

        model.isVisible = false
        await hosted.settle()
        #expect(model.primarySubscriptions == 0)
        #expect(model.secondarySubscriptions == 0)
    }

    private func findGrid(_ view: PlatformView) -> NativeGrid? {
        if let grid = view as? NativeGrid {
            return grid
        }
        return view.subviews.lazy
            .compactMap(findGrid)
            .first
    }

    private func displayedItemSize(_ grid: NativeGrid) throws -> CGSize {
        #if os(macOS)
        return try #require(
            grid.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        ).size
        #else
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        return try #require(
            collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        ).size
        #endif
    }

    private func availableWidth(_ grid: NativeGrid) throws -> CGFloat {
        #if os(macOS)
        return grid.scrollView.contentSize.width
        #else
        return try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first).bounds.width
        #endif
    }
}

@MainActor
private final class RemeasurementModel: ObservableObject {

    @Published
    var showsTitle = false

    @Published
    var usesSecondary = false

    @Published
    var isVisible = true

    let primary = PassthroughSubject<Int, Never>()
    let secondary = PassthroughSubject<Int, Never>()
    var primarySubscriptions = 0
    var secondarySubscriptions = 0

    var publisher: AnyPublisher<Int, Never> {
        if usesSecondary {
            return secondary
                .handleEvents(
                    receiveSubscription: { [weak self] _ in
                        self?.secondarySubscriptions += 1
                    },
                    receiveCancel: { [weak self] in
                        self?.secondarySubscriptions -= 1
                    }
                )
                .eraseToAnyPublisher()
        }
        return primary
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.primarySubscriptions += 1
                },
                receiveCancel: { [weak self] in
                    self?.primarySubscriptions -= 1
                }
            )
            .eraseToAnyPublisher()
    }
}

private struct RemeasurementItem: View {

    let showsTitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.blue)
                .frame(height: 50)

            if showsTitle {
                Text("A title")
                    .lineLimit(1)
            }
        }
    }
}

private struct RemeasurementGrid: View {

    @ObservedObject
    var model: RemeasurementModel

    let sizing: CollectionVGridLayout.ItemSizing

    var body: some View {
        if model.isVisible {
            let showsTitle = model.showsTitle
            CollectionVGrid(
                count: 100,
                layout: .columns(
                    2,
                    insets: .init(),
                    itemSpacing: 0,
                    itemSizing: sizing
                )
            ) { _ in
                RemeasurementItem(showsTitle: showsTitle)
            }
            .remeasureItems(on: model.publisher)
        }
    }
}

@MainActor
private final class RemeasurementHost {

    #if os(macOS)
    let controller: NSHostingController<RemeasurementGrid>
    let window: NSWindow
    #else
    let controller: UIHostingController<RemeasurementGrid>
    let window: UIWindow
    #endif

    var view: PlatformView {
        controller.view
    }

    init(model: RemeasurementModel, sizing: CollectionVGridLayout.ItemSizing) {
        let content = RemeasurementGrid(model: model, sizing: sizing)
        #if os(macOS)
        _ = NSApplication.shared
        controller = NSHostingController(rootView: content)
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(CGSize(width: 300, height: 400))
        window.orderBack(nil)
        #else
        controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        #endif
    }

    func settle() async {
        layout()
        try? await Task.sleep(for: .milliseconds(80))
        layout()
    }

    private func layout() {
        #if os(macOS)
        view.layoutSubtreeIfNeeded()
        #else
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #endif
    }

    func close() {
        #if os(macOS)
        window.close()
        #else
        window.isHidden = true
        #endif
    }
}
