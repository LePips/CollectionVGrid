import DifferenceKit
import SwiftUI

// MARK: Comparable

extension Comparable {

    @inlinable
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(limits.upperBound, Swift.max(limits.lowerBound, self))
    }
}

// MARK: FloatingPoint

extension BinaryFloatingPoint {

    @inlinable
    var isFiniteAndPositive: Bool {
        isFinite && self > 0
    }

    @inlinable
    func positiveFinite(or fallback: Self) -> Self {
        isFiniteAndPositive ? self : fallback
    }
}

/// Layout dimensions must be finite and nonnegative; invalid values become zero.
@inlinable
func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? max(value, 0) : 0
}

// MARK: CGSize/CGFloat math

func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
    .init(
        width: lhs.width * rhs,
        height: lhs.height * rhs
    )
}

// MARK: Collection

extension Collection {

    @inlinable
    var isNotEmpty: Bool {
        !isEmpty
    }
}

// MARK: EdgeInsets

extension EdgeInsets {

    #if canImport(UIKit)
    var asUIEdgeInsets: UIEdgeInsets {
        .init(
            top: top,
            left: leading,
            bottom: bottom,
            right: trailing
        )
    }

    #endif

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

struct CollectionItem<Element, ID: Hashable>: Differentiable {
    let element: Element
    let id: ID
    var repetition: Int = 0

    struct Identity: Hashable {
        let id: ID
        let repetition: Int
    }

    var differenceIdentifier: Identity {
        Identity(id: id, repetition: repetition)
    }

    func isContentEqual(to source: Self) -> Bool {
        true
    }
}

#if canImport(UIKit)

// MARK: UICollectionView

extension UICollectionView {

    var flowLayout: UICollectionViewFlowLayout {
        collectionViewLayout as! UICollectionViewFlowLayout
    }

    var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get {
            showsVerticalScrollIndicator ? .visible : .hidden
        }
        set {
            switch newValue {
            case .automatic, .visible:
                showsVerticalScrollIndicator = true
            default:
                showsVerticalScrollIndicator = false
            }
        }
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

// MARK: - UIView

extension UIView {

    func closestUIViewController() -> UIViewController? {
        var responder: UIResponder? = self

        while responder != nil {
            if let vc = responder as? UIViewController {
                return vc
            }
            responder = responder?.next
        }

        return nil
    }
}

#endif

// MARK: View

extension View {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, to newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}
