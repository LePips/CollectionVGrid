import SwiftUI

struct GridItem: View {

    let color: Color
    let orientation: LayoutOrientation

    var body: some View {
        switch orientation {
        case .landscape:
            color
                .aspectRatio(1.77, contentMode: .fill)
                .cornerRadius(5)
        case .portrait:
            color
                .aspectRatio(0.66, contentMode: .fill)
                .cornerRadius(5)
        }
    }
}
