#if os(macOS)
import AppKit
import SwiftUI

final class CollectionDocumentView: NSCollectionView {
    override var isFlipped: Bool {
        true
    }

    override func setFrameSize(_ newSize: NSSize) {
        // AppKit can propose a viewport-sized frame while retiling a scroll view.
        // Our layout owns the document extent, including items outside that viewport.
        if let layout = collectionViewLayout as? CollectionLayout, enclosingScrollView != nil {
            super.setFrameSize(layout.collectionViewContentSize)
        } else {
            super.setFrameSize(newSize)
        }
    }
}

final class CollectionScrollView: NSScrollView {
    var allowsScrolling = true
    var didScroll: (() -> Void)?
    var willScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard allowsScrolling else { return }
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            willScroll?()
        }
        super.scrollWheel(with: event)
        didScroll?()
    }
}

/// Keep the hosting view across reuse; changing the identity resets SwiftUI state for a new item.
final class HostingCollectionViewItem: NSCollectionViewItem {
    private var host: NSHostingView<AnyView>?

    override func loadView() {
        view = NSView()
    }

    func configure(_ content: some View, id: AnyHashable) {
        let root = AnyView(content.id(id))
        if let host {
            host.rootView = root
        } else {
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.topAnchor.constraint(equalTo: view.topAnchor),
                host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            self.host = host
        }
    }
}

/// Uniform layouts compute only attributes intersecting the viewport, regardless of data count.
/// Variadic horizontal layouts cache column offsets and use binary search when scrolling.
final class CollectionLayout: NSCollectionViewLayout {
    var horizontal = false
    var lanes = 1
    var itemSize = CGSize.zero
    var insets = NSEdgeInsetsZero
    var itemSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var variableSizes: [CGSize] = []
    private var columnOffsets: [CGFloat] = []
    private var columnWidths: [CGFloat] = []

    var count: Int {
        guard let collectionView, collectionView.numberOfSections > 0 else { return 0 }
        return collectionView.numberOfItems(inSection: 0)
    }

    var groups: Int {
        count == 0 ? 0 : (count - 1) / max(lanes, 1) + 1
    }

    override func prepare() {
        super.prepare()
        guard horizontal, variableSizes.isNotEmpty, columnOffsets.isEmpty else { return }
        var offset = insets.left
        for group in 0 ..< groups {
            let start = group * lanes
            let width = variableSizes[start ..< min(start + lanes, variableSizes.count)].map(\.width).max() ?? 0
            columnOffsets.append(offset)
            columnWidths.append(width)
            offset += width + itemSpacing
        }
    }

    override func invalidateLayout() {
        columnOffsets.removeAll(keepingCapacity: true)
        columnWidths.removeAll(keepingCapacity: true)
        super.invalidateLayout()
    }

    override var collectionViewContentSize: NSSize {
        let viewport = collectionView?.enclosingScrollView?.contentSize ?? .zero
        if horizontal {
            let width = columnOffsets.last.map { $0 + (columnWidths.last ?? 0) + insets.right }
                ?? (insets.left + CGFloat(groups) * (itemSize.width + itemSpacing) - (groups > 0 ? itemSpacing : 0) + insets.right)
            return CGSize(width: max(viewport.width, width), height: viewport.height)
        }
        let height = insets.top + CGFloat(groups) * (itemSize.height + lineSpacing)
            - (groups > 0 ? lineSpacing : 0) + insets.bottom
        return CGSize(width: viewport.width, height: max(viewport.height, height))
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < count else { return nil }
        let group = indexPath.item / max(lanes, 1)
        let lane = indexPath.item % max(lanes, 1)
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        let size = variableSizes.indices.contains(indexPath.item) ? variableSizes[indexPath.item] : itemSize
        let x: CGFloat
        let y: CGFloat
        if horizontal {
            x = columnOffsets.indices.contains(group) ? columnOffsets[group] : insets.left + CGFloat(group) * (itemSize.width + itemSpacing)
            y = insets.top + CGFloat(lane) * (itemSize.height + lineSpacing)
        } else {
            x = insets.left + CGFloat(lane) * (itemSize.width + itemSpacing)
            y = insets.top + CGFloat(group) * (itemSize.height + lineSpacing)
        }
        attributes.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        return attributes
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard groups > 0 else { return [] }
        let lower = horizontal ? rect.minX : rect.minY
        let upper = horizontal ? rect.maxX : rect.maxY
        let inset = horizontal ? insets.left : insets.top
        let stride = max(1, horizontal ? itemSize.width + itemSpacing : itemSize.height + lineSpacing)
        let first: Int
        let last: Int
        if columnOffsets.isNotEmpty {
            first = max(0, columnIndex(at: lower) - 1)
            last = min(groups - 1, columnIndex(at: upper) + 1)
        } else {
            first = Int(floor((lower - inset) / stride).clamped(to: 0 ... CGFloat(groups - 1)))
            last = Int(floor((upper - inset) / stride).clamped(to: 0 ... CGFloat(groups - 1)))
        }
        guard first <= last else { return [] }
        return (first * lanes ..< min((last + 1) * lanes, count)).compactMap {
            let attributes = layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
            return attributes?.frame.intersects(rect) == true ? attributes : nil
        }
    }

    private func columnIndex(at x: CGFloat) -> Int {
        var low = 0
        var high = columnOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if columnOffsets[mid] <= x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        // Preserve cached metrics while scrolling, but let AppKit refresh its cached content size on resize.
        newBounds.size != collectionView?.bounds.size
    }
}

extension EdgeInsets {
    var appKitInsets: NSEdgeInsets {
        NSEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

func measuredContentSize(_ content: some View, width: CGFloat? = nil) -> CGSize {
    let measurement = ContentMeasurement()
    let root = ContentMeasurementLayout(width: width, measurement: measurement) { content.frame(width: width) }
    let host = NSHostingView(rootView: root)
    _ = host.fittingSize
    return CGSize(width: nonnegativeFinite(measurement.size.width), height: nonnegativeFinite(measurement.size.height))
}
#endif
