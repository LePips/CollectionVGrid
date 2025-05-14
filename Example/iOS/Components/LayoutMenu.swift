import SwiftUI

struct LayoutMenu: View {

    @Binding
    private var orientation: LayoutOrientation
    @Binding
    private var layout: LayoutType

    init(orientation: Binding<LayoutOrientation>, layout: Binding<LayoutType>) {
        self._orientation = orientation
        self._layout = layout
    }

    var body: some View {
        Menu("Layout", systemImage: "ellipsis.circle.fill") {
            Section("Orientation") {
                Button {
                    orientation = .landscape
                } label: {
                    if orientation == .landscape {
                        Label(LayoutOrientation.landscape.rawValue, systemImage: "checkmark")
                    } else {
                        Label(LayoutOrientation.landscape.rawValue, systemImage: "rectangle.fill")
                    }
                }

                Button {
                    orientation = .portrait
                } label: {
                    if orientation == .portrait {
                        Label(LayoutOrientation.portrait.rawValue, systemImage: "checkmark")
                    } else {
                        Label(LayoutOrientation.portrait.rawValue, systemImage: "rectangle.portrait.fill")
                    }
                }
            }

            Section("Layout") {
                Button {
                    layout = .grid
                } label: {
                    if layout == .grid {
                        Label(LayoutType.grid.rawValue, systemImage: "checkmark")
                    } else {
                        Label(LayoutType.grid.rawValue, systemImage: "square.grid.2x2.fill")
                    }
                }

                Button {
                    layout = .list
                } label: {
                    if layout == .list {
                        Label(LayoutType.list.rawValue, systemImage: "checkmark")
                    } else {
                        Label(LayoutType.list.rawValue, systemImage: "square.fill.text.grid.1x2")
                    }
                }
            }
        }
    }
}
