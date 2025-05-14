import CollectionVGrid
import SwiftUI

struct ContentView: View {

    @StateObject
    var proxy = CollectionVGridProxy()

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                _GridView()
            }
            
            Tab("Settings", systemImage: "gearshape") {
                _GridView()
            }
        }
        .ignoresSafeArea()
    }
}

private struct _GridView: View {
    
    @State
    var colors = (0 ..< 100).map { colorWheel(radius: $0) }
    
    let vGridLayout: CollectionVGridLayout = .columns(
        6,
        insets: .init(50),
        itemSpacing: 50,
        lineSpacing: 50
    )
    
    var body: some View {
        CollectionVGrid(
            uniqueElements: colors,
            id: \.self,
            layout: vGridLayout
        ) { color in
            Button {
                
            } label: {
                GridItem(color: color, orientation: .landscape)
            }
            .buttonStyle(.card)
        }
        .onReachedBottomEdge(offset: .offset(100)) {
            Task {
                try await Task.sleep(for: .seconds(1))
                
                await MainActor.run {
                    colors.append(contentsOf: (0 ..< 100).map { colorWheel(radius: $0) })
                }
            }
        }
        .ignoresSafeArea()
    }
}
