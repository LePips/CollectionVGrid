#if os(iOS)
@testable import CollectionVGrid
import QuartzCore
import SwiftUI
import Testing

/// Checks rendered artwork and captions, not just collection layout attributes.
@Suite(.serialized)
@MainActor
struct PosterResizeStressTests {
    @Test(arguments: [false, true])
    func `fractional poster resizing stays contained and virtualized`(adaptive: Bool) async throws {
        let counters = PosterResizeCounters()
        let layout: CollectionVGridLayout = adaptive ? .minWidth(160) : .columns(4)
        let data = Array(0 ..< 10000)
        let grid = UICollectionVGrid(
            id: \.self, data: data, layout: layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil
        ) { index, location in
            if location.column < 0 {
                counters.measurements += 1
            } else {
                counters.configurations += 1
            }
            return StressPoster(title: ["Dark Matter", "鱿鱼游戏：真人挑战赛", "A longer title that reserves two lines"][index % 3])
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 700))
        controller.view.addSubview(grid)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        grid.update(data: data, layout: layout, isScrollEnabled: true, verticalScrollIndicatorVisibility: .automatic)
        let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never

        // Each step is smaller than a physical pixel, including column changes.
        let fine = (0 ... 32).map { CGFloat(859) + CGFloat($0) / 8 }
        let widths = fine + fine.reversed() + [390, 1024, 768, 834, 1100]
        let started = ContinuousClock.now
        var layoutMilliseconds: [Double] = []
        var previousWidth: CGFloat?
        for (iteration, width) in widths.enumerated() {
            let layoutStarted = CACurrentMediaTime()
            grid.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            grid.setNeedsLayout()
            grid.layoutIfNeeded()
            if iteration == fine.count {
                collection.contentOffset.y = 1200
            }
            collection.layoutIfNeeded()
            if collection.bounds.width != previousWidth {
                layoutMilliseconds.append((CACurrentMediaTime() - layoutStarted) * 1000)
                previousWidth = collection.bounds.width
            }
            try await Task.sleep(for: .milliseconds(10))
            collection.layoutIfNeeded()

            #expect(collection.numberOfItems(inSection: 0) == data.count)
            #expect(!collection.visibleCells.isEmpty)
            try #require(
                collection.visibleCells.count < 100,
                "Frame \(iteration), viewport \(collection.bounds), first item \(String(describing: collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame))"
            )
            let expectedWidth = layout.itemWidth(for: collection.bounds.width).width
            for cell in collection.visibleCells {
                let artwork = try #require(marker("poster-artwork", in: cell))
                let caption = try #require(marker("poster-caption", in: cell))
                let imageFrame = artwork.convert(artwork.bounds, to: cell)
                let textFrame = caption.convert(caption.bounds, to: cell)
                #expect(abs(cell.bounds.width - expectedWidth) < 0.51)
                #expect(abs(imageFrame.width - expectedWidth) < 0.51)
                #expect(abs(imageFrame.height - imageFrame.width * 1.5) < 0.51)
                #expect(abs(imageFrame.minY) < 0.51)
                #expect(textFrame.minY >= imageFrame.maxY - 0.51)
                #expect(
                    textFrame.maxY <= cell.bounds.maxY + 0.51,
                    "Width \(width): caption bottom \(textFrame.maxY), cell height \(cell.bounds.height)"
                )
            }

            // Repeated layout at a settled width must not repeat measurement.
            let measurements = counters.measurements
            for _ in 0 ..< 3 {
                grid.setNeedsLayout()
                grid.layoutIfNeeded()
                collection.layoutIfNeeded()
            }
            #expect(counters.measurements == measurements)
        }
        #expect(
            counters.measurements <= widths.count + 2,
            "Measure a representative item per new width, never all 10,000 items"
        )
        #expect(
            counters.configurations < 1000,
            "Retained cells must resize without rebuilding every visible root"
        )
        layoutMilliseconds.sort()
        let p95 = layoutMilliseconds[Int(Double(layoutMilliseconds.count - 1) * 0.95)]
        print(
            "Poster resize stress: adaptive=\(adaptive), frames=\(widths.count), measurements=\(counters.measurements), configurations=\(counters.configurations), layout p95=\(p95)ms, elapsed=\(started.duration(to: .now))"
        )
    }

    private func marker(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { marker(identifier, in: $0) }.first
    }
}

private final class PosterResizeCounters {
    var measurements = 0
    var configurations = 0
}

private struct PosterFrameMarker: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = identifier
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct StressPoster: View {
    let title: String

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.blue
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .background(PosterFrameMarker(identifier: "poster-artwork"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(title)
                    .font(.footnote)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PosterFrameMarker(identifier: "poster-caption"))
            }
        }
        .buttonStyle(.borderless)
    }
}
#endif
