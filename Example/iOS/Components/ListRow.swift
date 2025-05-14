import SwiftUI

struct ListRow: View {

    @State
    private var contentSize: CGSize = .zero

    let color: Color
    let orientation: LayoutOrientation

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .center) {
                GridItem(color: color, orientation: orientation)
                    .frame(width: orientation == .landscape ? 110 : 60)
                    .padding(.vertical, 10)

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(color.description)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(String(repeating: "A", count: Int.random(in: 4 ..< 12)))
                            .font(.caption)
                            .foregroundColor(Color(UIColor.lightGray))
                            .redacted(reason: .placeholder)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .trackingSize($contentSize)
            }

            Color.secondary
                .opacity(0.75)
                .frame(width: contentSize.width, height: 1)
        }
        .padding(.horizontal)
    }
}
