import SwiftUI

struct LayoutMenu: View {
    @Binding var orientation: LayoutOrientation
    @Binding var layout: LayoutType
    @Binding var columns: Int
    @Binding var itemCount: Int

    var body: some View {
        Menu("Layout", systemImage: "slider.horizontal.3") {
            Picker("Layout", selection: $layout) {
                Text("Adaptive").tag(LayoutType.adaptive)
                Text("Columns").tag(LayoutType.grid)
                Text("List").tag(LayoutType.list)
            }
            Picker("Orientation", selection: $orientation) {
                Text("Landscape").tag(LayoutOrientation.landscape)
                Text("Portrait").tag(LayoutOrientation.portrait)
            }
            if layout == .grid {
                Picker("Columns", selection: $columns) {
                    ForEach(1 ... 8, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Picker("Items", selection: $itemCount) {
                Text("100").tag(100)
                Text("1,000").tag(1000)
                Text("10,000").tag(10000)
            }
        }
    }
}
