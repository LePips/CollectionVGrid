import SwiftUI

func colorWheel(radius: Int) -> Color {
    Color(hue: Double(radius % 360) / 360, saturation: 1, brightness: 1)
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension EdgeInsets {

    static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

extension View {

    func onSizeChanged(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { reader in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: reader.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}
