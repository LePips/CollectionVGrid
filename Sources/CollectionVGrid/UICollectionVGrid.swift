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

    private var data: Data
    private var header: CollectionHeader?
    private var itemMeasurementRevision = 0
    private var itemSize: CGSize?
    private var itemSizeCache = ItemSizeCache()
    private var lastLaidOutWidth: CGFloat?
    private var layout: CollectionVGridLayout
    private var layoutInvalidationGeneration = 0
    private var needsSizingUpdate = true
    private var onReachedBottomEdge: () -> Void
    private var onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedTopEdge: () -> Void
    private var onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedEdgeStore: Set<Edge>
    private var viewProvider: (Element, CollectionVGridLocation) -> Content

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

        let flowLayout = UICollectionViewFlowLayout()
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

    // MARK: layoutSubviews

    override public func layoutSubviews() {
        super.layoutSubviews()

        // Auto Layout can pixel-align the collection to a slightly different width.
        // Use the outer width only until the collection has its initial bounds.
        updateItemSize(forWidth: collectionView.bounds.width.positiveFinite(or: bounds.width))
        let headerSize = header?.size(forWidth: collectionView.bounds.width) ?? .zero
        if collectionView.flowLayout.headerReferenceSize != headerSize {
            collectionView.flowLayout.headerReferenceSize = headerSize
            invalidateCollectionLayout()
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

    private func refreshVisibleItems() {
        for path in collectionView.indexPathsForVisibleItems {
            guard (0 ..< itemCount).contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? HostingCollectionViewCell<Content> else { continue }

            let item = item(at: path.item)
            let location = CollectionVGridLocation(column: path.item % max(columns, 1), row: path.item / max(columns, 1))
            cell.setup(view: viewProvider(element(at: path.item), location), id: AnyHashable(item.differenceIdentifier))
        }
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
        viewProvider: ((Element, CollectionVGridLocation) -> Content)? = nil
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
        refreshVisibleItems()

        // layout

        if layoutChanged {
            layout = newLayout

            collectionView.flowLayout.sectionInset = newLayout.insets.asUIEdgeInsets
            collectionView.flowLayout.minimumLineSpacing = nonnegativeFinite(newLayout.lineSpacing)
            collectionView.flowLayout.minimumInteritemSpacing = nonnegativeFinite(newLayout.itemSpacing)

            // little animation to make instant change a little prettier
            // TODO: - figure out cell size animation if desired

            snapshotReload()
        } else if hasDataChanges || wasEmpty != newData.isEmpty || measurementChanged {
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

        let element = element(at: indexPath.item)
        let location = CollectionVGridLocation(column: indexPath.row % columns, row: indexPath.row / columns)
        cell.setup(view: viewProvider(element, location), id: AnyHashable(item(at: indexPath.item).differenceIdentifier))
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

        // A size delegate must not invalidate or force the layout that is calling it.
        itemSize ?? computeItemSize(forWidth: collectionView.bounds.width.positiveFinite(or: bounds.width)).itemSize
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

    private func updateItemSize(forWidth width: CGFloat) {
        guard width.isFiniteAndPositive, needsSizingUpdate || lastLaidOutWidth != width else { return }

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

#endif
