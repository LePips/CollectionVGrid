import DifferenceKit
import SwiftUI

// TODO: sections of items?
// TODO: customize layout change animation?
// TODO: figure out refreshable
//       - deadlocks when using environment `RefreshAction`
// TODO: infinite
//       - like CollectionHStack carousel
// TODO: full paging scrolling layout?
// TODO: reverse layout
//       - bottom to top, like Photos app
// TODO: prefetching
//       - like CollectionHStack

public protocol _UICollectionVGrid: UIView {

    func snapshotReload()
    func scrollToTop(animated: Bool)
}

// MARK: UICollectionVGrid

public class UICollectionVGrid<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>:
    UIView,
    _UICollectionVGrid,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout
    where Data.Element == Element, Data.Index == Int
{

    private var _id: KeyPath<Element, ID>

    private var columns: Int
    private var currentElementIDHashes: [Int]
    private var data: Data
    private var measuredItemAspectRatio: CGFloat?
    private var itemSize: CGSize?
    private var lastLaidOutWidth: CGFloat?
    private var layout: CollectionVGridLayout
    private var layoutInvalidationGeneration = 0
    private var needsSizingUpdate = true
    private let onReachedBottomEdge: () -> Void
    private let onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    private let onReachedTopEdge: () -> Void
    private let onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedEdgeStore: Set<Edge>
    private var viewProvider: (Element, CollectionVGridLocation) -> Content

    // MARK: init

    public init(
        id: KeyPath<Element, ID>,
        data: Data,
        layout: CollectionVGridLayout,
        onReachedBottomEdge: @escaping () -> Void,
        onReachedBottomEdgeOffset: CollectionVGridEdgeOffset,
        onReachedTopEdge: @escaping () -> Void,
        onReachedTopEdgeOffset: CollectionVGridEdgeOffset,
        proxy: CollectionVGridProxy?,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self._id = id
        self.columns = 1
        self.currentElementIDHashes = []
        self.data = data
        self.layout = layout
        self.onReachedBottomEdge = onReachedBottomEdge
        self.onReachedBottomEdgeOffset = onReachedBottomEdgeOffset
        self.onReachedTopEdge = onReachedTopEdge
        self.onReachedTopEdgeOffset = onReachedTopEdgeOffset
        self.onReachedEdgeStore = []
        self.viewProvider = viewProvider

        super.init(frame: .zero)

        if let proxy {
            proxy.collectionVGrid = self
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var collectionView: UICollectionView = {

        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.sectionInset = layout.insets.asUIEdgeInsets
        flowLayout.minimumLineSpacing = layout.lineSpacing
        flowLayout.minimumInteritemSpacing = layout.itemSpacing

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(
            HostingCollectionViewCell<Content>.self,
            forCellWithReuseIdentifier: cellReuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = nil

        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        return collectionView
    }()

    // MARK: layoutSubviews

    override public func layoutSubviews() {
        super.layoutSubviews()

        updateItemSize(forWidth: bounds.width)

        if let viewController = closestUIViewController() {
            viewController.setContentScrollView(collectionView)
        }
    }

    // MARK: update

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateSizing()
        }
    }

    func update(
        data newData: Data,
        layout newLayout: CollectionVGridLayout,
        isScrollEnabled: Bool,
        verticalScrollIndicatorVisibility: ScrollIndicatorVisibility,
        viewProvider: ((Element, CollectionVGridLocation) -> Content)? = nil
    ) {

        let wasEmpty = data.isEmpty
        let layoutChanged = newLayout != layout

        if let viewProvider {
            self.viewProvider = viewProvider
        }

        // data

        let newIDs = newData
            .map { $0[keyPath: _id].hashValue }

        let changes = StagedChangeset(
            source: currentElementIDHashes,
            target: newIDs,
            section: 0
        )

        let hasDataChanges = !changes.isEmpty
        data = newData

        if hasDataChanges {
            collectionView.reload(using: changes) { newHashes in
                self.currentElementIDHashes = newHashes
            }
        }

        // layout

        if layoutChanged {
            layout = newLayout

            collectionView.flowLayout.sectionInset = newLayout.insets.asUIEdgeInsets
            collectionView.flowLayout.minimumLineSpacing = newLayout.lineSpacing
            collectionView.flowLayout.minimumInteritemSpacing = newLayout.itemSpacing

            // little animation to make instant change a little prettier
            // TODO: - figure out cell size animation if desired

            snapshotReload()
        } else if hasDataChanges || wasEmpty != newData.isEmpty {
            invalidateSizing()
        }

        collectionView.isScrollEnabled = isScrollEnabled
        collectionView.verticalScrollIndicatorVisibility = verticalScrollIndicatorVisibility
    }

    public func snapshotReload() {

        invalidateSizing()

        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.reloadData()
            return
        }

        addSubview(snapshot)

        NSLayoutConstraint.activate([
            snapshot.topAnchor.constraint(equalTo: topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: bottomAnchor),
            snapshot.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        collectionView.alpha = 0
        collectionView.reloadData()

        UIView.animate(withDuration: 0.1) {
            snapshot.alpha = 0
            self.collectionView.alpha = 1
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    public func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(
            .init(
                x: 0,
                y: -collectionView.adjustedContentInset.top
            ),
            animated: animated
        )
    }

    // MARK: UICollectionViewDataSource

    public func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        currentElementIDHashes.count
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: cellReuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell<Content>

        let item = data[indexPath.row % currentElementIDHashes.count]
        let location = CollectionVGridLocation(column: indexPath.row % columns, row: indexPath.row / columns)
        cell.setup(view: viewProvider(item, location))
        return cell
    }

    // MARK: UICollectionViewDelegate

    /// required for tvOS
    public func collectionView(
        _ collectionView: UICollectionView,
        canFocusItemAt indexPath: IndexPath
    ) -> Bool {
        false
    }

    // MARK: UICollectionViewDelegateFlowLayout

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        if itemSize == nil {
            updateItemSize(forWidth: bounds.width)
        }

        return itemSize ?? .zero
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {

        guard scrollView.contentSize.height > 0 else { return }

        // top edge

        handleReachedTopEdge(with: scrollView.contentOffset.y)

        // bottom edge

        handleReachedBottomEdge(with: scrollView.contentOffset.y)
    }

    private func handleReachedTopEdge(with contentOffset: CGFloat) {

        let reachedTop: Bool

        switch onReachedTopEdgeOffset {
        case let .offset(offset):
            reachedTop = collectionView.contentOffset.y <= offset
        case let .rows(rows):
            let minIndexPath = collectionView
                .indexPathsForVisibleItems
                .map(\.row)
                .min() ?? Int.max

            reachedTop = minIndexPath < itemCount(inRows: rows)
        }

        if reachedTop {
            if !onReachedEdgeStore.contains(.top) {
                onReachedEdgeStore.insert(.top)
                onReachedTopEdge()
            }
        } else {
            onReachedEdgeStore.remove(.top)
        }
    }

    private func handleReachedBottomEdge(with contentOffset: CGFloat) {

        let reachedBottom: Bool

        switch onReachedBottomEdgeOffset {
        case let .offset(offset):
            let reachBottomPosition = collectionView.contentSize.height - offset
            reachedBottom = collectionView.contentOffset.y + collectionView.bounds.height >= reachBottomPosition &&
                collectionView.contentOffset.y > 0
        case let .rows(rows):
            let maxIndexPath = collectionView
                .indexPathsForVisibleItems
                .map(\.row)
                .max() ?? Int.min
            let itemCount = itemCount(inRows: rows)
            let firstBottomRowIndex = itemCount >= currentElementIDHashes.count
                ? 0
                : currentElementIDHashes.count - itemCount

            reachedBottom = maxIndexPath >= firstBottomRowIndex
        }

        if reachedBottom {
            if !onReachedEdgeStore.contains(.bottom) {
                onReachedEdgeStore.insert(.bottom)
                onReachedBottomEdge()
            }
        } else {
            onReachedEdgeStore.remove(.bottom)
        }
    }

    // MARK: item size

    /// Computes a stable item size from the supplied width rather than reading `bounds`
    /// throughout the calculation. This keeps every step of a live resize on one width.
    func computeItemSize(forWidth availableWidth: CGFloat) -> (columns: Int, itemSize: CGSize) {
        guard availableWidth.isFinite, availableWidth > 0 else { return (1, .zero) }

        let resolvedWidth: (width: CGFloat, columns: Int) = switch layout.layoutType {
        case .columns:
            itemWidth(
                availableWidth: availableWidth,
                columns: validColumnCount(layout.layoutValue)
            )
        case .minWidth:
            itemWidth(
                availableWidth: availableWidth,
                minimumWidth: validMinimumWidth(layout.layoutValue)
            )
        }

        return (resolvedWidth.columns, measuredItemSize(width: resolvedWidth.width))
    }

    private func updateItemSize(forWidth width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        guard needsSizingUpdate || lastLaidOutWidth != width else { return }

        let resolvedSize = computeItemSize(forWidth: width)
        let newItemSize = resolvedSize.itemSize
        let itemSizeChanged = itemSize != newItemSize

        columns = resolvedSize.columns
        itemSize = newItemSize
        lastLaidOutWidth = width
        needsSizingUpdate = false

        guard itemSizeChanged else { return }

        // Keep UICollectionViewFlowLayout's cached metrics in sync immediately.
        // During iPad window transitions, invalidating delegate metrics alone can
        // leave its itemSize and existing attributes at the pre-transition width.
        collectionView.flowLayout.itemSize = newItemSize
        invalidateCollectionLayout()
    }

    private func invalidateCollectionLayout() {
        collectionView.collectionViewLayout.invalidateLayout()

        // `super.layoutSubviews()` has already laid out the collection view for this
        // pass. Rebuild its attributes now so the old item width is not displayed for
        // an extra frame during a window or split-view transition.
        collectionView.layoutIfNeeded()

        // UIKit can reject the forced child layout while a scene-geometry transaction
        // is active. Coalesce one reconciliation pass onto the next run-loop turn.
        layoutInvalidationGeneration += 1
        let generation = layoutInvalidationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.layoutInvalidationGeneration == generation else { return }

            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        }
    }

    private func invalidateSizing() {
        needsSizingUpdate = true
        lastLaidOutWidth = nil
        itemSize = nil
        measuredItemAspectRatio = nil
        setNeedsLayout()
    }

    private func measuredItemSize(width: CGFloat) -> CGSize {
        guard !data.isEmpty, width.isFinite, width > 0 else {
            return CGSize(width: nonnegativeFinite(width), height: 0)
        }

        if let measuredItemAspectRatio {
            return CGSize(
                width: width,
                height: nonnegativeFinite(width / measuredItemAspectRatio)
            )
        }

        let view = AnyView(
            viewProvider(data[0], .init(column: -1, row: -1))
                .frame(width: width)
        )

        // Remeasure after invalidation, then reuse the measured ratio while resizing.
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = nil
        hostingController.view.sizeToFit()
        let measuredSize = hostingController.view.bounds.size

        // Hosting views can round their bounds. Derive the ratio from the measured
        // width and height together, then apply it to the requested item width.
        let ratio = measuredSize.width / measuredSize.height
        if ratio.isFinite, ratio > 0 {
            measuredItemAspectRatio = ratio
            return CGSize(width: width, height: nonnegativeFinite(width / ratio))
        }
        return CGSize(width: width, height: nonnegativeFinite(measuredSize.height))
    }

    private func validColumnCount(_ columns: CGFloat) -> Int {
        guard columns.isFinite, columns > 0 else { return 1 }
        return Int(min(floor(columns), CGFloat(Int.max).nextDown))
    }

    private func validMinimumWidth(_ minimumWidth: CGFloat) -> CGFloat {
        guard minimumWidth.isFinite, minimumWidth > 0 else { return 1 }
        return minimumWidth
    }

    private func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func itemCount(inRows rows: Int) -> Int {
        guard rows > 0 else { return 0 }
        let (itemCount, overflow) = rows.multipliedReportingOverflow(by: columns)
        return overflow ? Int.max : itemCount
    }

    // MARK: item width

    private func itemWidth(
        availableWidth: CGFloat,
        columns: Int
    ) -> (width: CGFloat, columns: Int) {
        let itemSpaces = CGFloat(max(columns - 1, 0))
        let itemSpacing = itemSpaces * collectionView.flowLayout.minimumInteritemSpacing
        let totalNegative = collectionView.flowLayout.sectionInset.horizontal + itemSpacing
        let width = (availableWidth - totalNegative) / CGFloat(columns)

        return (nonnegativeFinite(width), columns)
    }

    private func itemWidth(
        availableWidth: CGFloat,
        minimumWidth: CGFloat
    ) -> (width: CGFloat, columns: Int) {
        let layout = collectionView.flowLayout
        let contentWidth = max(availableWidth - layout.sectionInset.horizontal, 0)
        let widthAndSpacing = minimumWidth + layout.minimumInteritemSpacing
        let rawColumns: CGFloat = if widthAndSpacing > 0 {
            max(floor((contentWidth + layout.minimumInteritemSpacing) / widthAndSpacing), 1)
        } else {
            1
        }
        let columns = Int(min(rawColumns, CGFloat(Int.max).nextDown))

        return itemWidth(availableWidth: availableWidth, columns: columns)
    }
}
