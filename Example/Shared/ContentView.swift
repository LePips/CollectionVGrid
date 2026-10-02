import CollectionVGrid
import Combine
import SwiftUI

struct ContentView: View {

    @State
    private var layout = LayoutType.adaptive

    @State
    private var orientation = LayoutOrientation.landscape

    @State
    private var columns = 4

    @State
    private var itemCount = 1000

    @State
    private var colorOffset = 0

    @State
    private var showsTitles = false

    @State
    private var itemSizeChanges = PassthroughSubject<Void, Never>()

    @StateObject
    private var proxy = CollectionVGridProxy()

    private var gridLayout: CollectionVGridLayout {
        switch layout {
        case .adaptive:
            .minWidth(orientation == .landscape ? 180 : 120)
        case .grid:
            .columns(columns)
        case .list:
            .columns(1, itemSizing: .height)
        }
    }

    var body: some View {
        NavigationStack {
            CollectionVGrid(count: itemCount, layout: gridLayout) { index in
                VStack(alignment: .leading, spacing: 8) {
                    if layout == .list {
                        ListRow(color: colorWheel(radius: index + colorOffset), orientation: orientation)
                    } else {
                        GridItem(color: colorWheel(radius: index + colorOffset), orientation: orientation)
                    }

                    if showsTitles {
                        Text("Item \(index + 1)")
                            .font(.caption)
                            .lineLimit(1)
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
            .remeasureItems(on: itemSizeChanges)
            #if os(iOS)
            .ignoresSafeArea()
            #endif
            .navigationTitle("CollectionVGrid")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup {
                    Button("Scroll to top", systemImage: "arrow.up.to.line") {
                        proxy.scrollToTop()
                    }
                    LayoutMenu(
                        orientation: $orientation,
                        layout: $layout,
                        columns: $columns,
                        itemCount: $itemCount,
                        showsTitles: $showsTitles
                    )
                    NavigationLink {
                        InfiniteGridView()
                    } label: {
                        Label("Load more example", systemImage: "infinity")
                    }
                }
            }
        }
        .onChange(of: orientation) {
            itemSizeChanges.send()
        }
        .onChange(of: layout) {
            itemSizeChanges.send()
        }
        .onChange(of: showsTitles) {
            itemSizeChanges.send()
        }
    }
}

#Preview {
    ContentView()
}
