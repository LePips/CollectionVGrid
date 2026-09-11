import Foundation
import SwiftUI

// TODO: layout validation and correction

public struct CollectionVGridLayout: Equatable {

    public let insets: EdgeInsets
    public let itemSpacing: CGFloat
    public let lineSpacing: CGFloat

    var layoutValue: CGFloat
    var layoutType: LayoutType

    private init(
        insets: EdgeInsets,
        itemSpacing: CGFloat,
        lineSpacing: CGFloat,
        layoutValue: CGFloat,
        layoutType: LayoutType
    ) {
        self.insets = insets
        self.itemSpacing = itemSpacing
        self.lineSpacing = lineSpacing
        self.layoutValue = layoutValue
        self.layoutType = layoutType
    }

    enum LayoutType {
        case columns
        case minWidth
    }

    // MARK: cases

    public static func columns(
        _ columns: Int,
        insets: EdgeInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10),
        itemSpacing: CGFloat = 10,
        lineSpacing: CGFloat = 10
    ) -> CollectionVGridLayout {
        .init(
            insets: insets,
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            layoutValue: CGFloat(columns),
            layoutType: .columns
        )
    }

    public static func minWidth(
        _ minWidth: CGFloat,
        insets: EdgeInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10),
        itemSpacing: CGFloat = 10,
        lineSpacing: CGFloat = 10
    ) -> CollectionVGridLayout {
        .init(
            insets: insets,
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            layoutValue: minWidth,
            layoutType: .minWidth
        )
    }
}
