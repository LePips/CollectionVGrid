import CollectionVGrid
import OrderedCollections
import SwiftUI

struct ContentView: View {

    @State
//    var colors = OrderedSet((0 ..< 360).map { colorWheel(radius: $0) })
    var numbers = OrderedSet(Array(0 ..< 360))
    @State
    var orientation: LayoutOrientation = .landscape
    @State
    var layout: LayoutType = .grid
    @State
    var listRowContentWidth: CGFloat = 0
    @State
    var vGridLayout: CollectionVGridLayout = .columns(3)

    @StateObject
    var proxy = CollectionVGridProxy<Int>()

    var body: some View {
        NavigationView {
            CollectionVGrid(
                $numbers,
                layout: $vGridLayout
            ) { color in
                switch layout {
                case .grid:
                    GridItem(color: colorWheel(radius: color), orientation: orientation)
                case .list:
                    ListRow(color: colorWheel(radius: color), orientation: orientation)
                }
            }
            .proxy(proxy)
            .refreshable {
                print("here")
                
                try! await Task.sleep(nanoseconds: 2_000_000_000)
                
                print("there")
            }
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
        .onChange(of: orientation) { newValue in
            switch (newValue, layout) {
            case (.landscape, .grid):
                vGridLayout = .columns(3)
            case (.portrait, .grid):
                vGridLayout = .columns(4)
            case (_, .list):
                proxy.layout()
                vGridLayout = .columns(1, insets: .zero, itemSpacing: 0, lineSpacing: 0)
            }
        }
        .onChange(of: layout) { newValue in
            switch (orientation, newValue) {
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
