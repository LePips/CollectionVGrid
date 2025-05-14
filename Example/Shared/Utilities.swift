import SwiftUI

enum LayoutOrientation: String {
    case landscape = "Landscape"
    case portrait = "Portrait"
}

enum LayoutType: String {
    case grid = "Grid"
    case list = "List"
}

func colorWheel(radius: Int) -> Color {
    Color(hue: Double(radius % 360) / 360, saturation: 1, brightness: 1)
}

extension EdgeInsets {

    static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    
    init(_ constant: CGFloat) {
        self.init(
            top: constant,
            leading: constant,
            bottom: constant,
            trailing: constant
        )
    }
}

extension View {
    
    func trackingSize(_ binding: Binding<CGSize>) -> some View {
        onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            binding.wrappedValue = size
        }
    }
}
