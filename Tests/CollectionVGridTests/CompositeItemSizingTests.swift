@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CompositeItemSizingTests {
    @Test(arguments: [false, true])
    func `default sizing measures artwork and wrapping captions at each width`(adaptive: Bool) {
        let configuration = CollectionVGrid(
            count: 10000,
            layout: adaptive ? .minWidth(120) : .columns(6)
        ) { _ in CompositePoster() }
        #if os(macOS)
        let grid = NSCollectionVGrid(configuration: configuration)
        defer { grid.disconnect() }
        #else
        let grid = UICollectionVGrid(
            id: \.self, data: configuration.data, layout: configuration.layout,
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .rows(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .rows(0), proxy: nil,
            viewProvider: configuration.viewProvider
        )
        #endif

        for width: CGFloat in [834, 390, 1024, 768, 834] {
            let size = grid.computeItemSize(forWidth: width).itemSize
            let content = CompositePoster().frame(width: size.width).fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            let host = NSHostingController(rootView: content)
            #else
            let host = UIHostingController(rootView: content)
            #endif
            let expected = host.sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude))
            #expect(abs(size.height - expected.height) < 1)
        }
    }
}

private struct CompositePoster: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.blue.aspectRatio(2 / 3, contentMode: .fill)
            Text("鱿鱼游戏：真人挑战赛 — A collection of stories")
                .font(.footnote)
                .lineLimit(2, reservesSpace: true)
        }
    }
}
