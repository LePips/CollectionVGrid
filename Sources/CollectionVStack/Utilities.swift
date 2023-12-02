import DifferenceKit
import SwiftUI

// MARK: CGSize/CGFloat math

func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
    .init(
        width: lhs.width * rhs,
        height: lhs.height * rhs
    )
}

// MARK: EdgeInsets

extension EdgeInsets {

    var asUIEdgeInsets: UIEdgeInsets {
        .init(
            top: top,
            left: leading,
            bottom: bottom,
            right: trailing
        )
    }

    init(_ constant: CGFloat) {
        self.init(
            top: constant,
            leading: constant,
            bottom: constant,
            trailing: constant
        )
    }

    static let zero: EdgeInsets = .init(.zero)
}

// MARK: Int

extension Int: ContentEquatable, ContentIdentifiable {}

// MARK: UICollectionView

extension UICollectionView {

    var flowLayout: UICollectionViewFlowLayout {
        collectionViewLayout as! UICollectionViewFlowLayout
    }
}

// MARK: UIEdgeInsets

extension UIEdgeInsets {

    var horizontal: CGFloat {
        left + right
    }

    var vertical: CGFloat {
        top + bottom
    }
}

// MARK: UIViewRepresentable

extension UIViewRepresentable {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, to newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}

// MARK: View

extension View {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, to newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}
