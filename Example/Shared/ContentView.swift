import CollectionVGrid
import SwiftUI

struct ContentView: View {
    @State private var layout = LayoutType.adaptive
    @State private var orientation = LayoutOrientation.landscape
    @State private var columns = 4
    @State private var itemCount = 1000
    @State private var colorOffset = 0
    @StateObject private var proxy = CollectionVGridProxy()

    private var gridLayout: CollectionVGridLayout {
        switch layout {
        case .adaptive:
            .minWidth(orientation == .landscape ? 180 : 120)
        case .grid:
            .columns(columns)
        case .list:
            .columns(1)
        }
    }

    var body: some View {
        NavigationStack {
            CollectionVGrid(count: itemCount, layout: gridLayout) { index in
                Group {
                    if layout == .list {
                        ListRow(color: colorWheel(radius: index + colorOffset), orientation: orientation)
                    } else {
                        GridItem(color: colorWheel(radius: index + colorOffset), orientation: orientation)
                    }
                }
                .exampleFocusable()
            }
            .proxy(proxy)
            #if os(iOS)
            .onRefresh {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                    colorOffset += 1
                } catch {
                    // Leave the colors unchanged if the refresh is cancelled.
                }
            }
            #endif
            .navigationTitle("CollectionVGrid")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup {
                    Button("Scroll to top", systemImage: "arrow.up.to.line") {
                        proxy.scrollToTop()
                    }
                    LayoutMenu(orientation: $orientation, layout: $layout, columns: $columns, itemCount: $itemCount)
                    NavigationLink {
                        InfiniteGridView()
                    } label: {
                        Label("Load more example", systemImage: "infinity")
                    }
                }
            }
        }
        .onChange(of: orientation) { proxy.redraw() }
        .onChange(of: layout) { proxy.redraw() }
    }
}

#Preview {
    ContentView()
}
