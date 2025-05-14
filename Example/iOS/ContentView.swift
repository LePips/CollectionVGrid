import CollectionVGrid
import SwiftUI

struct ContentView: View {

    @State
    var orientation: LayoutOrientation = .landscape
    @State
    var layout: LayoutType = .grid
    @State
    var vGridLayout: CollectionVGridLayout = .columns(3)

    @StateObject
    var proxy = CollectionVGridProxy()
    
    let colors = (0 ..< 360).map { colorWheel(radius: $0) }

    var body: some View {
        NavigationView {
            CollectionVGrid(
                uniqueElements: colors,
                id: \.self,
                layout: vGridLayout
            ) { color in
                switch layout {
                case .grid:
                    GridItem(color: color, orientation: orientation)
                case .list:
                    ListRow(color: color, orientation: orientation)
                }
            }
            .scrollIndicatorsVisible(false)
            .proxy(proxy)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("CollectionVGrid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    LayoutMenu(orientation: $orientation, layout: $layout)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: orientation) {
            switch (orientation, layout) {
            case (.landscape, .grid):
                vGridLayout = .columns(3)
            case (.portrait, .grid):
                vGridLayout = .columns(4)
            case (_, .list):
                proxy.layout()
                vGridLayout = .columns(1, insets: .zero, itemSpacing: 0, lineSpacing: 0)
            }
        }
        .onChange(of: layout) {
            switch (orientation, layout) {
            case (.landscape, .grid):
                vGridLayout = .columns(3)
            case (.portrait, .grid):
                vGridLayout = .columns(4)
            case (_, .list):
                vGridLayout = .columns(1, insets: .zero, itemSpacing: 0, lineSpacing: 0)
            }
        }
    }
}
