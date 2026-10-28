#if os(macOS)
import AppKit
import SwiftUI

@MainActor
public protocol _NSCollectionVGrid: AnyObject {
    func snapshotReload()
    func scrollToTop(animated: Bool)
}

extension CollectionVGrid: NSViewRepresentable {
    public typealias NSViewType = NSCollectionVGrid<Element, Data, ID, Content>

    public func makeNSView(context: Context) -> NSViewType {
        NSViewType(configuration: self)
    }

    public func updateNSView(_ view: NSViewType, context: Context) {
        view.update(
            configuration: self,
            isScrollEnabled: context.environment.isScrollEnabled,
            indicatorVisibility: context.environment.verticalScrollIndicatorVisibility,
            dynamicTypeSize: context.environment.dynamicTypeSize
        )
    }

    public static func dismantleNSView(_ view: NSViewType, coordinator: ()) {
        view.disconnect()
    }
}

/// A native, reusable collection whose layout work scales with the visible rows.
public final class NSCollectionVGrid<Element, Data: Collection, ID: Hashable, Content: View>: NSView,
_NSCollectionVGrid where Data.Element == Element, Data.Index == Int {
    private var configuration: CollectionVGrid<Element, Data, ID, Content>
    let scrollView = CollectionScrollView()
    let collectionView = CollectionDocumentView()
    let collectionLayout = CollectionLayout()
    private var dataSource: NSCollectionViewDiffableDataSource<Int, ID>!
    private var dataIndex = CollectionDataIndex<ID>()
    private var indicesByID: [ID: Int] = [:]
    private var ids: [ID] {
        dataIndex.ids
    }

    private var updating = false
    private var header: CollectionHeader?
    private var itemSizeCache = ItemSizeCache()
    private var appliedWidth: CGFloat?
    private var dynamicTypeSize: DynamicTypeSize?
    private var reachedEdges: Set<Edge> = []
    private var scrollWork: DispatchWorkItem?
    private var disconnected = false
    private var scrollAnchor: ScrollAnchor?
    private var anchoredOffset: CGFloat?
    private var isApplyingLayout = false

    /// The position to preserve when the grid reflows for a new width. Recorded once,
    /// then reused across consecutive resizes so rounded offsets cannot accumulate drift.
    private enum ScrollAnchor {
        case top
        case bottom
        /// An item at the top of the viewport, offset by a fraction of its height,
        /// or by points when the viewport begins above the item (in a gap or the header).
        case item(index: Int, offset: CGFloat, isProportional: Bool)
    }

    init(configuration: CollectionVGrid<Element, Data, ID, Content>) {
        self.configuration = configuration
        super.init(frame: .zero)
        collectionView.collectionViewLayout = collectionLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(HostingCollectionViewItem.self, forItemWithIdentifier: .init("content"))
        collectionView.register(
            HostingCollectionViewHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: .init("header")
        )
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        dataSource = NSCollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collection, path, id in
            guard let self, let element = self.element(at: path.item, id: id) else { return nil }

            let item = collection.makeItem(withIdentifier: .init("content"), for: path) as! HostingCollectionViewItem
            item.configure(self.configuration.viewProvider(element, self.location(at: path.item)), id: AnyHashable(id))
            return item
        }
        dataSource.supplementaryViewProvider = { [weak self] collection, kind, path in
            guard let header = self?.header else { return nil }

            let view = collection.makeSupplementaryView(ofKind: kind, withIdentifier: .init("header"), for: path)
                as! HostingCollectionViewHeader
            header.attach(to: view)
            return view
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        update(configuration: configuration, isScrollEnabled: true, indicatorVisibility: .automatic, dynamicTypeSize: .large)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override public func layout() {
        super.layout()
        let width = scrollView.contentSize.width
        guard width.isFiniteAndPositive else { return }

        let headerHeight = header?.size(forWidth: width).height ?? 0
        if appliedWidth == width, collectionLayout.headerHeight == headerHeight {
            let contentSize = collectionLayout.collectionViewContentSize
            if collectionView.frame.size != contentSize {
                collectionView.setFrameSize(contentSize)
            }
            return
        }
        // Record the position against the outgoing layout before any metrics change.
        let anchor = appliedWidth.map { $0 != width } == true ? scrollAnchor ?? currentScrollAnchor() : nil
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        let result = computeItemSize(forWidth: width)
        let previousColumns = collectionLayout.lanes
        collectionLayout.lanes = result.columns
        collectionLayout.itemSize = result.itemSize
        collectionLayout.insets = configuration.layout.insets.appKitInsets
        collectionLayout.itemSpacing = nonnegativeFinite(configuration.layout.itemSpacing)
        collectionLayout.lineSpacing = nonnegativeFinite(configuration.layout.lineSpacing)
        collectionLayout.headerHeight = headerHeight
        collectionLayout.invalidateLayout()
        collectionView.setFrameSize(collectionLayout.collectionViewContentSize)
        appliedWidth = width
        if let anchor {
            scrollAnchor = anchor
            restoreScrollPosition(to: anchor)
        }
        if previousColumns != result.columns {
            refreshVisibleItems()
        }
        scheduleScrollUpdate()
    }

    func update(
        configuration new: CollectionVGrid<Element, Data, ID, Content>,
        isScrollEnabled: Bool,
        indicatorVisibility: ScrollIndicatorVisibility,
        dynamicTypeSize: DynamicTypeSize
    ) {
        let changedLayout = configuration.layout != new.layout || self.dynamicTypeSize != dynamicTypeSize
        let changedMeasurement = configuration.itemMeasurementRevision != new.itemMeasurementRevision
        if configuration.proxy !== new.proxy, configuration.proxy?.collectionVGrid === self {
            configuration.proxy?.collectionVGrid = nil
        }
        let changedData = dataIndex.update(from: new.data, id: new._id, prefix: nil, retainingLookup: &indicesByID)
        updating = changedData
        configuration = new
        if let content = new.headerContent {
            if let header {
                header.update(content: content)
            } else {
                header = CollectionHeader(content: content)
            }
        } else {
            header?.detach()
            header = nil
        }
        self.dynamicTypeSize = dynamicTypeSize
        new.proxy?.collectionVGrid = self
        scrollView.allowsScrolling = isScrollEnabled
        scrollView.hasVerticalScroller = isScrollEnabled && indicatorVisibility != .hidden
        scrollView.verticalScroller?.isEnabled = isScrollEnabled
        if changedData || changedLayout || changedMeasurement {
            invalidateSizing()
        }
        if changedData {
            scrollAnchor = nil
            anchoredOffset = nil
        }
        if changedData || collectionView.numberOfSections == 0 {
            var snapshot = NSDiffableDataSourceSnapshot<Int, ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            updating = true
            dataSource.apply(snapshot, animatingDifferences: false)
            updating = false
            reachedEdges.removeAll()
        } else {
            refreshVisibleItems()
        }
        needsLayout = true
        scheduleScrollUpdate()
    }

    private func element(at position: Int, id: ID) -> Element? {
        if !updating, (0 ..< ids.count).contains(position) {
            return dataIndex.element(in: configuration.data, at: position)
        }
        guard let sourceIndex = indicesByID[id] else { return nil }

        return configuration.data[sourceIndex]
    }

    private func refreshVisibleItems() {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: path), let element = element(at: path.item, id: id),
                  let item = collectionView.item(at: path) as? HostingCollectionViewItem else { continue }

            item.configure(configuration.viewProvider(element, location(at: path.item)), id: AnyHashable(id))
        }
    }

    private func location(at index: Int) -> CollectionVGridLocation {
        let columns = max(1, collectionLayout.lanes)
        return CollectionVGridLocation(column: index % columns, row: index / columns)
    }

    private func invalidateSizing() {
        header?.invalidateSize()
        itemSizeCache = ItemSizeCache()
        appliedWidth = nil
        needsLayout = true
    }

    func computeItemSize(forWidth width: CGFloat) -> (columns: Int, itemSize: CGSize) {
        guard width.isFiniteAndPositive else { return (1, .zero) }

        let resolvedWidth = configuration.layout.itemWidth(for: width)
        let columns = resolvedWidth.columns
        let itemWidth = resolvedWidth.width
        guard !ids.isEmpty, itemWidth > 0 else { return (columns, CGSize(width: itemWidth, height: 0)) }

        let element = dataIndex.element(in: configuration.data, at: 0)
        let size = itemSizeCache.size(width: itemWidth, sizing: configuration.layout.itemSizing) {
            measuredContentSize(configuration.viewProvider(element, .init(column: -1, row: -1)), width: itemWidth)
        }
        return (columns, size)
    }

    public func snapshotReload() {
        invalidateSizing()
        refreshVisibleItems()
    }

    public func scrollToTop(animated: Bool) {
        scrollAnchor = nil
        anchoredOffset = nil
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                scrollView.contentView.animator().setBoundsOrigin(.zero)
            }
        } else {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        scheduleScrollUpdate()
    }

    // MARK: scroll anchoring

    private var maximumOffset: CGFloat {
        max(0, collectionLayout.collectionViewContentSize.height - scrollView.contentView.bounds.height)
    }

    private func currentScrollAnchor() -> ScrollAnchor? {
        guard ids.isNotEmpty else { return nil }

        let viewport = scrollView.contentView.bounds
        if viewport.minY <= 0.5 {
            return .top
        }
        if viewport.minY >= maximumOffset - 0.5 {
            return .bottom
        }
        let first = collectionLayout.layoutAttributesForElements(in: viewport)
            .filter { $0.representedElementCategory == .item && $0.frame.maxY > viewport.minY && $0.frame.height.isFiniteAndPositive }
            .min { ($0.frame.minY, $0.indexPath?.item ?? 0) < ($1.frame.minY, $1.indexPath?.item ?? 0) }
        guard let first, let index = first.indexPath?.item else { return nil }

        let isProportional = first.frame.minY <= viewport.minY
        return .item(
            index: index,
            offset: isProportional ? (viewport.minY - first.frame.minY) / first.frame.height : viewport.minY - first.frame.minY,
            isProportional: isProportional
        )
    }

    private func restoreScrollPosition(to anchor: ScrollAnchor) {
        let target: CGFloat
        switch anchor {
        case .top:
            target = 0
        case .bottom:
            target = maximumOffset
        case let .item(index, offset, isProportional):
            guard let attributes = collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }

            target = attributes.frame.minY + (isProportional ? offset * attributes.frame.height : offset)
        }
        let offset = target.clamped(to: 0 ... maximumOffset)
        anchoredOffset = offset
        guard abs(offset - scrollView.contentView.bounds.minY) > 0.001 else { return }

        scrollView.contentView.scroll(to: CGPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc
    private func boundsChanged() {
        // Any other movement establishes a new position to preserve on the next resize.
        let tolerance = 1 / max(window?.backingScaleFactor ?? 1, 1)
        if !isApplyingLayout, let anchoredOffset, abs(scrollView.contentView.bounds.minY - anchoredOffset) > tolerance {
            scrollAnchor = nil
            self.anchoredOffset = nil
        }
        if appliedWidth != scrollView.contentSize.width {
            needsLayout = true
        }
        scheduleScrollUpdate()
    }

    private func scheduleScrollUpdate() {
        scrollWork?.cancel()
        guard !disconnected else { return }

        let work = DispatchWorkItem { [weak self] in self?.publishScrollState() }
        scrollWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func publishScrollState() {
        guard ids.isNotEmpty else { return }

        let viewport = scrollView.contentView.bounds
        let visible = collectionView.indexPathsForVisibleItems().map(\.item)
        let columns = max(1, collectionLayout.lanes)
        let top: Bool = switch configuration.onReachedTopEdgeOffset {
        case let .offset(offset): viewport.minY <= offset
        case let .rows(rows): visible.min().map { $0 / columns < rows } ?? false
        }
        let bottom: Bool = switch configuration.onReachedBottomEdgeOffset {
        case let .offset(offset): viewport.minY > 0 && viewport.maxY >= collectionLayout.collectionViewContentSize.height - offset
        case let .rows(rows): visible.max().map { $0 / columns >= collectionLayout.groups - rows } ?? false
        }
        updateEdge(.top, reached: top, action: configuration.onReachedTopEdge)
        updateEdge(.bottom, reached: bottom, action: configuration.onReachedBottomEdge)
    }

    private func updateEdge(_ edge: Edge, reached: Bool, action: () -> Void) {
        if reached {
            if reachedEdges.insert(edge).inserted {
                action()
            }
        } else {
            reachedEdges.remove(edge)
        }
    }

    func disconnect() {
        disconnected = true
        scrollWork?.cancel()
        if configuration.proxy?.collectionVGrid === self {
            configuration.proxy?.collectionVGrid = nil
        }
    }
}
#endif
