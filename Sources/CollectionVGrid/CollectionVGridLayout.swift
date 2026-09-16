import Foundation
import SwiftUI

// TODO: layout validation and correction

public struct CollectionVGridLayout: Equatable {

    /// The first item's measurement to reuse for all items during resizing.
    public enum ItemSizing: Equatable, Sendable {
        /// Cache the measured width-to-height ratio and scale height with item width.
        case aspectRatio
        /// Cache the measured height and keep it fixed as item width changes.
        case height
    }

    public let insets: EdgeInsets
    public let itemSpacing: CGFloat
    public let lineSpacing: CGFloat
    public let itemSizing: ItemSizing

    var layoutValue: CGFloat
    var layoutType: LayoutType

    private init(
        insets: EdgeInsets,
        itemSpacing: CGFloat,
        lineSpacing: CGFloat,
        itemSizing: ItemSizing,
        layoutValue: CGFloat,
        layoutType: LayoutType
    ) {
        self.insets = insets
        self.itemSpacing = itemSpacing
        self.lineSpacing = lineSpacing
        self.itemSizing = itemSizing
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
        lineSpacing: CGFloat = 10,
        itemSizing: ItemSizing = .aspectRatio
    ) -> CollectionVGridLayout {
        .init(
            insets: insets,
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            itemSizing: itemSizing,
            layoutValue: CGFloat(columns),
            layoutType: .columns
        )
    }

    public static func minWidth(
        _ minWidth: CGFloat,
        insets: EdgeInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10),
        itemSpacing: CGFloat = 10,
        lineSpacing: CGFloat = 10,
        itemSizing: ItemSizing = .aspectRatio
    ) -> CollectionVGridLayout {
        .init(
            insets: insets,
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            itemSizing: itemSizing,
            layoutValue: minWidth,
            layoutType: .minWidth
        )
    }
}
