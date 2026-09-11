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
    private var ids: [ID] = []
    private var elements: [Element] = []
    private var elementsByID: [ID: Element] = [:]
    private var itemSizeCache = ItemSizeCache()
    private var appliedWidth: CGFloat?
    private var dynamicTypeSize: DynamicTypeSize?
    private var reachedEdges: Set<Edge> = []
    private var scrollWork: DispatchWorkItem?
    private var disconnected = false

    init(configuration: CollectionVGrid<Element, Data, ID, Content>) {
        self.configuration = configuration
        super.init(frame: .zero)
        collectionView.collectionViewLayout = collectionLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(HostingCollectionViewItem.self, forItemWithIdentifier: .init("content"))
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
            guard let self, let element = self.elementsByID[id] else { return nil }
            let item = collection.makeItem(withIdentifier: .init("content"), for: path) as! HostingCollectionViewItem
            item.configure(self.configuration.viewProvider(element, self.location(at: path.item)), id: AnyHashable(id))
            return item
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
        if appliedWidth == width {
            let contentSize = collectionLayout.collectionViewContentSize
            if collectionView.frame.size != contentSize {
                collectionView.setFrameSize(contentSize)
            }
            return
        }
        let result = computeItemSize(forWidth: width)
        let previousColumns = collectionLayout.lanes
        collectionLayout.lanes = result.columns
        collectionLayout.itemSize = result.itemSize
        collectionLayout.insets = configuration.layout.insets.appKitInsets
        collectionLayout.itemSpacing = nonnegativeFinite(configuration.layout.itemSpacing)
        collectionLayout.lineSpacing = nonnegativeFinite(configuration.layout.lineSpacing)
        collectionLayout.invalidateLayout()
        collectionView.setFrameSize(collectionLayout.collectionViewContentSize)
        appliedWidth = width
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
        if configuration.proxy !== new.proxy, configuration.proxy?.collectionVGrid === self {
            configuration.proxy?.collectionVGrid = nil
        }
        configuration = new
        self.dynamicTypeSize = dynamicTypeSize
        new.proxy?.collectionVGrid = self
        scrollView.allowsScrolling = isScrollEnabled
        scrollView.hasVerticalScroller = isScrollEnabled && indicatorVisibility != .hidden
        scrollView.verticalScroller?.isEnabled = isScrollEnabled
        let newElements = Array(new.data)
        let newIDs = newElements.map { $0[keyPath: new._id] }
        precondition(Set(newIDs).count == newIDs.count, "CollectionVGrid requires unique element IDs")
        let changedData = newIDs != ids
        elements = newElements
        ids = newIDs
        elementsByID = Dictionary(uniqueKeysWithValues: zip(ids, elements))
        if changedData || changedLayout {
            invalidateSizing()
        }
        if changedData {
            var snapshot = NSDiffableDataSourceSnapshot<Int, ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            dataSource.apply(snapshot, animatingDifferences: false)
            reachedEdges.removeAll()
        } else {
            refreshVisibleItems()
        }
        needsLayout = true
        scheduleScrollUpdate()
    }

    private func refreshVisibleItems() {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: path), let element = elementsByID[id],
                  let item = collectionView.item(at: path) as? HostingCollectionViewItem else { continue }
            item.configure(configuration.viewProvider(element, location(at: path.item)), id: AnyHashable(id))
        }
    }

    private func location(at index: Int) -> CollectionVGridLocation {
        let columns = max(1, collectionLayout.lanes)
        return CollectionVGridLocation(column: index % columns, row: index / columns)
    }

    private func invalidateSizing() {
        itemSizeCache = ItemSizeCache()
        appliedWidth = nil
        needsLayout = true
    }

    func computeItemSize(forWidth width: CGFloat) -> (columns: Int, itemSize: CGSize) {
        guard width.isFiniteAndPositive else { return (1, .zero) }
        let resolvedWidth = configuration.layout.itemWidth(for: width)
        let columns = resolvedWidth.columns
        let itemWidth = resolvedWidth.width
        guard let element = elements.first, itemWidth > 0 else { return (columns, CGSize(width: itemWidth, height: 0)) }
        let size = itemSizeCache.size(width: itemWidth) {
            measuredContentSize(configuration.viewProvider(element, .init(column: -1, row: -1)), width: itemWidth)
        }
        return (columns, size)
    }

    public func snapshotReload() {
        invalidateSizing()
        refreshVisibleItems()
    }

    public func scrollToTop(animated: Bool) {
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

    @objc
    private func boundsChanged() {
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
