#if canImport(UIKit)
import DifferenceKit
import SwiftUI

// TODO: sections of items?
// TODO: customize layout change animation?
// TODO: infinite
//       - like CollectionHStack carousel
// TODO: full paging scrolling layout?
// TODO: reverse layout
//       - bottom to top, like Photos app
// TODO: prefetching
//       - like CollectionHStack

/// Visible content refreshes wait this long after the latest geometry change.
private let resizeSettleDelay: TimeInterval = 0.1

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
    private var dataIndex = CollectionDataIndex<ID>()
    private var stagedItems: [CollectionItem<ID>]?
    private var dataTransition: CollectionDataTransition<Data, ID>?
    private var itemCount: Int {
        stagedItems?.count ?? dataIndex.ids.count
    }

    private var isDataUpdateInProgress: Bool {
        stagedItems != nil
    }

    private var data: Data
    private var header: CollectionHeader?
    private var itemMeasurementRevision = 0
    private var itemSize: CGSize?
    private var itemSizeCache = ItemSizeCache()
    private var lastLaidOutWidth: CGFloat?
    private var layout: CollectionVGridLayout
    private var needsSizingUpdate = true
    private var onReachedBottomEdge: () -> Void
    private var onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedTopEdge: () -> Void
    private var onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedEdgeStore: Set<Edge>
    private var viewProvider: (Element, CollectionVGridLocation) -> Content

    // resizing
    private var contentGeneration = 0
    private var needsContentRefresh = false
    private var contentRefreshGeneration = 0
    private var lastGeometryChangeTime: CFTimeInterval = -.infinity
    /// Unlike `lastLaidOutWidth`, this survives sizing invalidation.
    private var lastAppliedWidth: CGFloat?
    private var scrollAnchor: ScrollAnchor?
    private var isAdjustingScrollPosition = false

    /// The position to preserve when the grid reflows for a new width. Recorded once,
    /// before the collection resizes, then reused across consecutive resizes so
    /// pixel-rounded offsets cannot accumulate drift.
    private enum ScrollAnchor {
        case top
        case bottom
        /// An item at the top of the visible area, offset by a fraction of its height,
        /// or by points when the area begins above the item (in a gap or the header).
        case item(index: Int, offset: CGFloat, isProportional: Bool)
    }

    #if os(iOS)
    private var refreshAction: (@MainActor () async -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    #endif

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

    deinit {
        #if os(iOS)
        refreshTask?.cancel()
        #endif
    }

    private lazy var collectionView: UICollectionView = {

        let flowLayout = CollectionVGridFlowLayout()
        flowLayout.sectionInset = layout.insets.asUIEdgeInsets
        flowLayout.minimumLineSpacing = nonnegativeFinite(layout.lineSpacing)
        flowLayout.minimumInteritemSpacing = nonnegativeFinite(layout.itemSpacing)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(
            HostingCollectionViewCell<Content>.self,
            forCellWithReuseIdentifier: cellReuseIdentifier
        )
        collectionView.register(
            HostingCollectionViewHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "header"
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

    // Auto Layout reflows the collection during layoutSubviews, so record the
    // scroll position while the outgoing layout is still in place.
    override public var bounds: CGRect {
        willSet {
            if newValue.width != bounds.width {
                recordScrollAnchor()
            }
        }
    }

    override public var frame: CGRect {
        willSet {
            if newValue.width != frame.width {
                recordScrollAnchor()
            }
        }
    }

    // MARK: layoutSubviews

    override public func layoutSubviews() {
        defer { refreshContentIfSettled() }
        // Resizing the collection can clamp its offset; that is not a new position.
        let wasAdjustingScrollPosition = isAdjustingScrollPosition
        isAdjustingScrollPosition = true
        defer { isAdjustingScrollPosition = wasAdjustingScrollPosition }
        super.layoutSubviews()

        // Auto Layout can pixel-align the collection to a slightly different width.
        // Use the outer width only until the collection has its initial bounds.
        var reflowed = updateItemSize(forWidth: collectionView.bounds.width.positiveFinite(or: bounds.width))
        let headerSize = header?.size(forWidth: collectionView.bounds.width) ?? .zero
        if collectionView.flowLayout.headerReferenceSize != headerSize {
            collectionView.flowLayout.headerReferenceSize = headerSize
            collectionView.collectionViewLayout.invalidateLayout()
            reflowed = true
        }
        if reflowed {
            // Position the reflowed content before laying out cells, so cells are
            // laid out once, at their final offset.
            if let scrollAnchor {
                restoreScrollPosition(to: scrollAnchor)
            }
            // The delegate already uses the current width, so finish this geometry
            // pass without queuing a second invalidation into the next animation frame.
            collectionView.layoutIfNeeded()
        }

        if let viewController = closestUIViewController() {
            viewController.setContentScrollView(collectionView)
        }
    }

    func configure(_ configuration: CollectionVGrid<Element, Data, ID, Content>) {
        if collectionView.contentInsetAdjustmentBehavior != configuration.contentInsetAdjustmentBehavior {
            collectionView.contentInsetAdjustmentBehavior = configuration.contentInsetAdjustmentBehavior
        }
        if let content = configuration.headerContent {
            if let header {
                header.update(content: content)
            } else {
                header = CollectionHeader(content: content)
            }
        } else {
            header?.detach()
            header = nil
        }
        setNeedsLayout()
        #if os(iOS)
        configureRefresh(action: configuration.refreshAction)
        #endif
        onReachedBottomEdge = configuration.onReachedBottomEdge
        onReachedBottomEdgeOffset = configuration.onReachedBottomEdgeOffset
        onReachedTopEdge = configuration.onReachedTopEdge
        onReachedTopEdgeOffset = configuration.onReachedTopEdgeOffset
        configuration.proxy?.collectionVGrid = self
    }

    #if os(iOS)
    func configureRefresh(action: (@MainActor () async -> Void)?) {
        refreshAction = action
        guard action != nil else {
            refreshGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            collectionView.refreshControl?.endRefreshing()
            collectionView.refreshControl = nil
            return
        }
        guard collectionView.refreshControl == nil else { return }

        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(didRequestRefresh), for: .valueChanged)
        collectionView.refreshControl = control
    }

    @objc
    private func didRequestRefresh() {
        guard refreshTask == nil, let action = refreshAction else { return }

        let generation = refreshGeneration

        // Start outside the control event/update pass so the action can suspend
        // and update the grid without blocking UIKit.
        refreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }

            await action()
            // A cancelled action may finish after refresh has been re-enabled.
            guard let self, self.refreshGeneration == generation else { return }

            self.collectionView.refreshControl?.endRefreshing()
            self.refreshTask = nil
        }
    }
    #endif

    // MARK: content refresh

    /// Supplies the latest views and locations to visible cells that predate the
    /// current content generation.
    private func refreshVisibleItems() {
        needsContentRefresh = false
        let visibleColumns = max(layout.itemWidth(for: collectionView.bounds.width).columns, 1)
        for path in collectionView.indexPathsForVisibleItems {
            guard (0 ..< itemCount).contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? HostingCollectionViewCell<Content>,
                  cell.contentGeneration != contentGeneration else { continue }

            configure(cell, at: path.item, columns: visibleColumns)
        }
    }

    /// Containers that adapt to their size update the grid on each resize frame, and
    /// collapsing bars change its insets on each scroll frame, usually without changing
    /// any item content. Visible cells are already laid out again, so refreshing their
    /// content as well would rebuild every hosted view each frame. Defer it until the
    /// geometry settles; cells that appear meanwhile are configured as usual.
    private func refreshContentIfSettled() {
        guard needsContentRefresh else { return }

        let remaining = lastGeometryChangeTime + resizeSettleDelay - CACurrentMediaTime()
        guard remaining > 0, window != nil else {
            refreshVisibleItems()
            return
        }

        contentRefreshGeneration &+= 1
        let generation = contentRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.contentRefreshGeneration == generation else { return }

            self.refreshContentIfSettled()
        }
    }

    private func configure(_ cell: HostingCollectionViewCell<Content>, at position: Int, columns: Int) {
        let location = CollectionVGridLocation(column: position % columns, row: position / columns)
        cell.setup(
            view: viewProvider(element(at: position), location),
            id: AnyHashable(item(at: position).differenceIdentifier),
            generation: contentGeneration
        )
    }

    // MARK: scroll anchoring

    /// Content offsets the collection can rest at, including adjusted content insets.
    /// The layout's own content size is current even before the collection lays out.
    private var scrollRange: ClosedRange<CGFloat> {
        let minimum = -collectionView.adjustedContentInset.top
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let maximum = contentHeight + collectionView.adjustedContentInset.bottom - collectionView.bounds.height
        return minimum ... max(minimum, maximum)
    }

    /// Records the leading item at the top of the visible area, unless a position
    /// from an earlier, uninterrupted resize is still in effect.
    private func recordScrollAnchor() {
        guard scrollAnchor == nil, lastAppliedWidth != nil, itemCount > 0, !isDataUpdateInProgress,
              collectionView.bounds.height.isFiniteAndPositive else { return }

        let offset = collectionView.contentOffset.y
        let range = scrollRange
        if offset <= range.lowerBound + 0.5 {
            scrollAnchor = .top
            return
        }
        if offset >= range.upperBound - 0.5 {
            scrollAnchor = .bottom
            return
        }

        let reference = offset + collectionView.adjustedContentInset.top
        let visible = CGRect(x: 0, y: reference, width: collectionView.bounds.width, height: collectionView.bounds.height)
        let first = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: visible)?
            .filter { $0.representedElementCategory == .cell && $0.frame.maxY > reference && $0.frame.height.isFiniteAndPositive }
            .min { ($0.frame.minY, $0.indexPath.item) < ($1.frame.minY, $1.indexPath.item) }
        guard let first else { return }

        let isProportional = first.frame.minY <= reference
        scrollAnchor = .item(
            index: first.indexPath.item,
            offset: isProportional ? (reference - first.frame.minY) / first.frame.height : reference - first.frame.minY,
            isProportional: isProportional
        )
    }

    /// Queries go through the collection view, which prepares an invalidated layout
    /// without laying out cells, so the new offset can be applied first. Called
    /// during layout, which already treats offset changes as adjustments.
    private func restoreScrollPosition(to anchor: ScrollAnchor) {
        // Never move content out from under the user's finger or momentum.
        guard !collectionView.isTracking, !collectionView.isDecelerating, !isDataUpdateInProgress, itemCount > 0 else { return }

        let target: CGFloat
        switch anchor {
        case .top:
            target = scrollRange.lowerBound

        case .bottom:
            _ = collectionView.layoutAttributesForItem(at: IndexPath(item: itemCount - 1, section: 0))
            target = scrollRange.upperBound

        case let .item(index, offset, isProportional):
            guard index < itemCount,
                  let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
            else { return }

            let distance = isProportional ? offset * attributes.frame.height : offset
            target = attributes.frame.minY + distance - collectionView.adjustedContentInset.top
        }

        let offset = target.clamped(to: scrollRange)
        guard abs(offset - collectionView.contentOffset.y) > 0.001 else { return }

        collectionView.contentOffset.y = offset
    }

    private func item(at position: Int) -> CollectionItem<ID> {
        stagedItems?[position] ?? dataIndex.item(at: position)
    }

    private func element(at position: Int) -> Element {
        if let stagedItems, let dataTransition {
            return dataTransition.element(for: stagedItems[position].id, in: data, index: dataIndex)
        }
        return dataIndex.element(in: data, at: position)
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
        itemMeasurementRevision: Int = 0,
        viewProvider: ((Element, CollectionVGridLocation) -> Content)? = nil,
        defersContentRefresh: Bool = false
    ) {

        let wasEmpty = data.isEmpty
        let layoutChanged = newLayout != layout
        let measurementChanged = self.itemMeasurementRevision != itemMeasurementRevision
        self.itemMeasurementRevision = itemMeasurementRevision

        if let viewProvider {
            self.viewProvider = viewProvider
        }

        // data

        var newIndex = dataIndex
        var lookup: [ID: Int]?
        let hasDataChanges = newIndex.update(from: newData, id: _id, prefix: nil, lookup: &lookup)
        if hasDataChanges {
            scrollAnchor = nil
            let source = dataIndex.items()
            let target = newIndex.items()
            let changes = StagedChangeset(source: source, target: target, section: 0)
            dataTransition = CollectionDataTransition(
                previousData: data, previousIndex: dataIndex, currentIndex: newIndex,
                lookup: &lookup, hasDeletions: changes.contains { !$0.elementDeleted.isEmpty }
            )
            stagedItems = source
            data = newData
            dataIndex = newIndex
            collectionView.reload(using: changes) { self.stagedItems = $0 }
            stagedItems = nil
            dataTransition = nil
        } else {
            data = newData
            dataIndex = newIndex
        }
        // layout

        // Bars collapsing while scrolling change only the top and bottom insets,
        // which leave item widths, and therefore measurements, unchanged.
        let changedVerticalInsetsOnly = layoutChanged && newLayout.differsOnlyInVerticalInsets(from: layout)
        if layoutChanged {
            layout = newLayout

            let flowLayout = collectionView.flowLayout
            if flowLayout.sectionInset != newLayout.insets.asUIEdgeInsets {
                flowLayout.sectionInset = newLayout.insets.asUIEdgeInsets
            }
            if flowLayout.minimumLineSpacing != nonnegativeFinite(newLayout.lineSpacing) {
                flowLayout.minimumLineSpacing = nonnegativeFinite(newLayout.lineSpacing)
            }
            if flowLayout.minimumInteritemSpacing != nonnegativeFinite(newLayout.itemSpacing) {
                flowLayout.minimumInteritemSpacing = nonnegativeFinite(newLayout.itemSpacing)
            }
        }
        // Safe-area and bar insets can change while the user is scrolling.
        // Relayout the existing cells; reloading them here discards hosted
        // SwiftUI state and restarts work such as loading artwork.
        if (layoutChanged && !changedVerticalInsetsOnly) || hasDataChanges || wasEmpty != newData.isEmpty || measurementChanged {
            invalidateSizing()
        } else if changedVerticalInsetsOnly {
            lastGeometryChangeTime = CACurrentMediaTime()
        }

        // Every visible cell, including those configured during staged updates,
        // now predates the latest data and view provider. SwiftUI lays out the
        // representable before rendering, which lets geometry changes skip the refresh.
        contentGeneration &+= 1
        let structuralChange = hasDataChanges || measurementChanged || (layoutChanged && !changedVerticalInsetsOnly)
        if !defersContentRefresh || structuralChange || window == nil {
            refreshVisibleItems()
        } else {
            needsContentRefresh = true
            setNeedsLayout()
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
        itemCount
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: cellReuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell<Content>

        configure(cell, at: indexPath.item, columns: columns)
        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: "header",
            for: indexPath
        )
        header?.attach(to: view)
        return view
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

        // UIKit may ask for metrics as soon as the child's bounds change, before
        // the wrapper's layoutSubviews runs. Never reuse a size from another width.
        // Keep this query free of layout invalidation and forced layout passes.
        let width = collectionView.bounds.width.positiveFinite(or: bounds.width)
        if lastLaidOutWidth == width, let itemSize {
            return itemSize
        }
        return computeItemSize(forWidth: width).itemSize
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {

        // Any other movement establishes a new position to preserve on the next resize.
        if !isAdjustingScrollPosition {
            scrollAnchor = nil
        }

        guard scrollView.contentSize.height > 0 else { return }

        // top edge

        handleReachedTopEdge()

        // bottom edge

        handleReachedBottomEdge()
    }

    private func handleReachedTopEdge() {

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

    private func handleReachedBottomEdge() {

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
            let firstBottomRowIndex = itemCount >= self.itemCount
                ? 0
                : self.itemCount - itemCount

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
        guard availableWidth.isFiniteAndPositive else { return (1, .zero) }

        let resolvedWidth = layout.itemWidth(for: availableWidth)
        let width = resolvedWidth.width
        // Flow layout subtracts each item and gap from the remaining row width.
        // A fractional quotient can round up just enough to wrap the last column.
        let fittingWidth = width.rounded(.down) == width ? width : width.nextDown

        return (resolvedWidth.columns, measuredItemSize(width: fittingWidth))
    }

    /// Returns whether the collection reflowed its items.
    private func updateItemSize(forWidth width: CGFloat) -> Bool {
        guard width.isFiniteAndPositive, needsSizingUpdate || lastLaidOutWidth != width else { return false }

        let resolvedSize = computeItemSize(forWidth: width)
        let newItemSize = resolvedSize.itemSize
        let itemSizeChanged = itemSize != newItemSize

        if resolvedSize.columns != columns {
            // Every visible cell's location changes with the column count.
            contentGeneration &+= 1
            needsContentRefresh = true
        }
        if let lastAppliedWidth, lastAppliedWidth != width {
            lastGeometryChangeTime = CACurrentMediaTime()
        }
        columns = resolvedSize.columns
        itemSize = newItemSize
        lastLaidOutWidth = width
        lastAppliedWidth = width
        needsSizingUpdate = false

        guard itemSizeChanged else { return false }

        // Keep UICollectionViewFlowLayout's cached metrics in sync immediately.
        // During iPad window transitions, invalidating delegate metrics alone can
        // leave its itemSize and existing attributes at the pre-transition width.
        collectionView.flowLayout.itemSize = newItemSize
        collectionView.collectionViewLayout.invalidateLayout()
        return true
    }

    private func invalidateSizing() {
        header?.invalidateSize()
        needsSizingUpdate = true
        lastLaidOutWidth = nil
        itemSize = nil
        itemSizeCache = ItemSizeCache()
        setNeedsLayout()
    }

    private func measuredItemSize(width: CGFloat) -> CGSize {
        guard data.isNotEmpty, width.isFiniteAndPositive else {
            return CGSize(width: nonnegativeFinite(width), height: 0)
        }

        return itemSizeCache.size(width: width, sizing: layout.itemSizing) {
            let measurement = ContentMeasurement()
            let root = ContentMeasurementLayout(width: width, measurement: measurement) {
                viewProvider(data[data.startIndex], .init(column: -1, row: -1)).frame(width: width)
            }
            let controller = UIHostingController(rootView: root)
            controller.safeAreaRegions.remove(.container)
            _ = controller.sizeThatFits(in: .zero)
            return measurement.size
        }
    }

    private func itemCount(inRows rows: Int) -> Int {
        guard rows > 0 else { return 0 }

        let (itemCount, overflow) = rows.multipliedReportingOverflow(by: columns)
        return overflow ? Int.max : itemCount
    }
}

class CollectionVGridFlowLayout: UICollectionViewFlowLayout {
    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if newBounds.width != collectionView?.bounds.width,
           let flowContext = context as? UICollectionViewFlowLayoutInvalidationContext
        {
            // Flow layout otherwise keeps delegate sizes from the previous width
            // while reflowing its attributes, which can briefly change row counts.
            flowContext.invalidateFlowLayoutDelegateMetrics = true
            flowContext.invalidateFlowLayoutAttributes = true
        }
        return context
    }
}

#endif
