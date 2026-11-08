#if os(iOS)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct PosterLayoutTests {
    @Test
    func `poster and caption are measured at each width`() {
        let grid = makeGrid()
        for width: CGFloat in [834, 390, 1024, 768, 834] {
            let size = grid.computeItemSize(forWidth: width).itemSize
            let host = UIHostingController(rootView: PosterFixture(title: "Dark Matter")
                .frame(width: size.width)
                .fixedSize(horizontal: false, vertical: true))
            let expected = host.sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude))
            #expect(
                abs(size.height - expected.height) < 1,
                "width \(width): allocated \(size.height), content needs \(expected.height)"
            )
        }
    }

    @Test
    func `mixed language posters stay aligned after resizing scrolling and sorting`() async throws {
        let grid = makeGrid()
        grid.update(
            data: Array(0 ..< 100),
            layout: .columns(6),
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic
        )
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 700))
        parent.view.addSubview(grid)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for data in [Array(0 ..< 100), Array((0 ..< 100).reversed())] {
            grid.update(
                data: data,
                layout: .columns(6),
                isScrollEnabled: true,
                verticalScrollIndicatorVisibility: .automatic
            )
            for width: CGFloat in [834, 390, 1024, 834] {
                grid.frame = CGRect(x: 0, y: 0, width: width, height: 700)
                grid.setNeedsLayout()
                grid.layoutIfNeeded()
                let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
                for offset: CGFloat in [0, 800, 0] {
                    collection.contentOffset.y = offset
                    collection.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    #expect(!collection.visibleCells.isEmpty)
                    for cell in collection.visibleCells {
                        let path = try #require(collection.indexPath(for: cell))
                        let artworkView = try #require(marker("artwork", in: cell))
                        let captionView = try #require(marker("caption", in: cell))
                        let artwork = artworkView.convert(artworkView.bounds, to: nil)
                        let caption = captionView.convert(captionView.bounds, to: nil)
                        let frame = cell.convert(cell.bounds, to: nil)
                        #expect(
                            abs(artwork.minY - frame.minY) < 1,
                            "item \(path.item), width \(width): poster top \(artwork.minY), cell top \(frame.minY)"
                        )
                        #expect(abs(artwork.height - artwork.width * 1.5) < 1)
                        #expect(caption.minY >= artwork.maxY)
                        #expect(
                            caption.maxY <= frame.maxY + 1,
                            "item \(path.item): caption ends \(caption.maxY), cell ends \(frame.maxY)"
                        )
                    }
                }
            }
        }
    }

    private func marker(_ kind: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == kind {
            return view
        }
        return view.subviews.lazy.compactMap { marker(kind, in: $0) }.first
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["COLLECTION_RESIZE_BENCHMARK"] == "1"))
    func `heavy mixed language resizing preserves poster and caption bounds`() async throws {
        let grid = makeGrid()
        var data = Array(0 ..< 10000)
        grid.update(
            data: data,
            layout: .columns(6),
            isScrollEnabled: true,
            verticalScrollIndicatorVisibility: .automatic
        )
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 700))
        parent.view.addSubview(grid)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var maxTopError: CGFloat = 0
        var maxCaptionOverflow: CGFloat = 0
        var maxArtworkError: CGFloat = 0
        var maxOverlap: CGFloat = 0
        var maxVisible = 0
        var checkedCells = 0
        for step in 0 ..< 1080 {
            if step.isMultiple(of: 100) {
                data.reverse()
                grid.update(
                    data: data,
                    layout: .columns(6),
                    isScrollEnabled: true,
                    verticalScrollIndicatorVisibility: .automatic
                )
            }
            let width = CGFloat(390 + (step * 37) % 951) + CGFloat(step % 3) / 3
            grid.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            grid.setNeedsLayout()
            grid.layoutIfNeeded()
            let collection = try #require(grid.subviews.compactMap { $0 as? UICollectionView }.first)
            collection.contentOffset.y = CGFloat((step / 50) % 6) * 430
            collection.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(4))
            collection.layoutIfNeeded()
            #expect(!collection.visibleCells.isEmpty)
            maxVisible = max(maxVisible, collection.visibleCells.count)
            for cell in collection.visibleCells {
                let artworkView = try #require(marker("artwork", in: cell))
                let captionView = try #require(marker("caption", in: cell))
                let artwork = artworkView.convert(artworkView.bounds, to: nil)
                let caption = captionView.convert(captionView.bounds, to: nil)
                let frame = cell.convert(cell.bounds, to: nil)
                maxTopError = max(maxTopError, abs(artwork.minY - frame.minY))
                maxCaptionOverflow = max(maxCaptionOverflow, caption.maxY - frame.maxY)
                maxArtworkError = max(maxArtworkError, abs(artwork.height - artwork.width * 1.5))
                maxOverlap = max(maxOverlap, artwork.maxY - caption.minY)
                checkedCells += 1
            }
        }
        #expect(maxTopError < 1)
        #expect(maxCaptionOverflow < 1)
        #expect(maxArtworkError < 1)
        #expect(maxOverlap < 1)
        #expect(maxVisible < 100)
        let record: [String: Any] = [
            "steps": 1080, "items": data.count, "checked_cells": checkedCells,
            "max_visible": maxVisible, "top_error_pt": maxTopError,
            "caption_overflow_pt": maxCaptionOverflow, "artwork_error_pt": maxArtworkError,
            "caption_overlap_pt": maxOverlap, "os": UIDevice.current.systemVersion,
        ]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("POSTER_STRESS \(String(decoding: json, as: UTF8.self))")
    }

    private func makeGrid() -> UICollectionVGrid<Int, [Int], Int, PosterFixture> {
        UICollectionVGrid(
            id: \.self, data: Array(0 ..< 100),
            layout: .columns(6, insets: .init(top: 10, leading: 10, bottom: 10, trailing: 10)),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil
        ) { index, _ in
            PosterFixture(title: ["Dark Matter", "鱿鱼游戏：真人挑战赛", "权力的游戏前传：龙族", "老友记"][index % 4])
        }
    }
}

private struct FrameMarker: UIViewRepresentable {
    let kind: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = kind
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct PosterFixture: View {
    let title: String

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading) {
                Color.blue
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .background(FrameMarker(kind: "artwork"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 2) {
                    Text(" ")
                    Text(" ")
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay(alignment: .topLeading) {
                    Text(title)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FrameMarker(kind: "caption"))
                }
            }
        }
        .buttonStyle(.borderless)
    }
}
#endif
