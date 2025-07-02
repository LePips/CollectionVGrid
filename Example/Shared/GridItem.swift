import SwiftUI

struct GridItem: View {

    let color: Color
    let orientation: LayoutOrientation

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color)
            .overlay(
                Text(color.description)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(4),
                alignment: .bottomTrailing
            )
            .aspectRatio(orientation == .landscape ? 1.77 : 0.66, contentMode: .fill)
            .shadow(radius: 4, y: 2)
    }
}
