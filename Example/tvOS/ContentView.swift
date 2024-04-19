import CollectionVGrid
import OrderedCollections
import SwiftUI

func colorWheel(radius: Int) -> Color {
    Color(hue: Double(radius) / 360, saturation: 1, brightness: 1)
}

extension EdgeInsets {

    init(_ constant: CGFloat) {
        self.init(
            top: constant,
            leading: constant,
            bottom: constant,
            trailing: constant
        )
    }
}

enum GridType: Equatable {
    case grid
    case list

    var layout: CollectionVGridLayout {
        switch self {
        case .grid:
            .columns(6, insets: .init(50), itemSpacing: 50, lineSpacing: 50)
        case .list:
            .columns(1)
        }
    }
}

struct ContentView: View {

    @State
    var colors = OrderedSet(0 ..< 36)
    @State
    var layout: CollectionVGridLayout = .columns(6, insets: .init(50), itemSpacing: 50, lineSpacing: 50)
    @State
    var gridType: GridType = .grid

    var body: some View {
        HStack {
            Color.red
                .opacity(0.5)
            
            CollectionVGrid(
                $colors,
                layout: $layout
            ) { color in
                Button {
                    switch gridType {
                    case .grid:
                        gridType = .list
                        layout = gridType.layout
                    case .list:
                        gridType = .grid
                        layout = gridType.layout
                    }
                } label: {
                    switch gridType {
                    case .grid:
                        colorWheel(radius: color)
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .cornerRadius(5)
                    case .list:
                        colorWheel(radius: color)
                            .frame(height: 100)
                            .cornerRadius(5)
                    }
                }
                .buttonStyle(.card)
            }
        }
    }
}
