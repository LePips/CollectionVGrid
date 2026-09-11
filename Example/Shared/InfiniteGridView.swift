import CollectionVGrid
import SwiftUI

struct InfiniteGridView: View {
    @State private var itemCount = 100
    @State private var isLoading = false

    var body: some View {
        CollectionVGrid(count: itemCount, layout: .minWidth(180)) { index in
            GridItem(color: colorWheel(radius: index), orientation: .landscape)
                .exampleFocusable()
        }
        .onReachedBottomEdge(offset: .rows(2)) {
            isLoading = true
        }
        .navigationTitle("Load more")
        .overlay(alignment: .bottom) {
            if isLoading {
                ProgressView("Loading more items")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
        .task(id: isLoading) {
            guard isLoading else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                itemCount += 100
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }
}
