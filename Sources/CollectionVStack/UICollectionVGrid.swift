import DifferenceKit
import SwiftUI

// TODO: sections of items?
// TODO: customize layout change animation?
// TODO: figure out refreshable
//       - deadlocks when using environment `RefreshAction`
// TODO: infinite
//       - like CollectionHStack carousel
// TODO: full paging scrolling layout?
// TODO: Fix TODO data bug below
//       - if updated too quickly, then currentElementIDs count != data count and
//         this will mainly lead to crashes with divide by 0/section count incorrect
//       - this will probably want to be fixed because `reloadData` has to be used
//         so this won't allow add/remove/move animations
// TODO: reverse layout
//       - bottom to top, like Photos app
// TODO: prefetching
//       - like CollectionHStack

public protocol _UICollectionVGrid: UIView {

    func snapshotReload()
}

// MARK: UICollectionVGrid

public class UICollectionVGrid<Element, Data: Collection, ID: Hashable>:
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
    private var itemSize: CGSize!
    private var layout: CollectionVGridLayout
    private let onReachedBottomEdge: () -> Void
    private let onReachedBottomEdgeOffset: CollectionVGridEdgeOffset
    private let onReachedTopEdge: () -> Void
    private let onReachedTopEdgeOffset: CollectionVGridEdgeOffset
    private var onReachedEdgeStore: Set<Edge>
    private var scrollIndicatorsVisible: Bool
    private let viewProvider: (Element, CollectionVGridLocation) -> any View

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
        scrollIndicatorsVisible: Bool,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> any View
    ) {
        self._id = id
        self.columns = 1
        self.currentElementIDHashes = []
        self.layout = layout
        self.data = data
        self.onReachedBottomEdge = onReachedBottomEdge
        self.onReachedBottomEdgeOffset = onReachedBottomEdgeOffset
        self.onReachedTopEdge = onReachedTopEdge
        self.onReachedTopEdgeOffset = onReachedTopEdgeOffset
        self.onReachedEdgeStore = []
        self.scrollIndicatorsVisible = scrollIndicatorsVisible
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
        collectionView.register(HostingCollectionViewCell.self, forCellWithReuseIdentifier: HostingCollectionViewCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = nil
        collectionView.showsVerticalScrollIndicator = scrollIndicatorsVisible

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

        itemSize = nil
        update(data: data, layout: layout)

        collectionView.performBatchUpdates {
            collectionView.flowLayout.invalidateLayout()
        }
    }

    // MARK: update

    // TODO: this seems to be called a lot when nothing changes
    func update(
        data newData: Data,
        layout newLayout: CollectionVGridLayout
    ) {

        // data

        let newIDs = newData
            .map { $0[keyPath: _id].hashValue }

        let changes = StagedChangeset(
            source: currentElementIDHashes,
            target: newIDs,
            section: 0
        )

        if !changes.isEmpty {
            data = newData

            // TODO: Fix if necessary? See comment at top of file.

//            collectionView.reload(using: changes) { _ in
//                self.currentElementIDHashes = newHashes
//            }

            currentElementIDHashes = newIDs
            collectionView.reloadData()
        }

        // layout

        if newLayout != layout {
            layout = newLayout

            itemSize = nil

            collectionView.flowLayout.sectionInset = newLayout.insets.asUIEdgeInsets
            collectionView.flowLayout.minimumLineSpacing = newLayout.lineSpacing
            collectionView.flowLayout.minimumInteritemSpacing = newLayout.itemSpacing

            // little animation to make instant change a little prettier
            // TODO: - figure out cell size animation if desired

            snapshotReload()
        }
    }

    public func snapshotReload() {

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

    // MARK: UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentElementIDHashes.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HostingCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell

        // TODO: Fix if necessary? See comment at top of file.

        let item = data[indexPath.row % currentElementIDHashes.count]
        let location = CollectionVGridLocation(column: indexPath.row % columns, row: indexPath.row / columns)
        cell.setupHostingView(with: viewProvider(item, location))
        return cell
    }

    // MARK: UICollectionViewDelegate

    // required for tvOS
    public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        false
    }

    // MARK: UICollectionViewDelegateFlowLayout

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        if let itemSize {
            return itemSize
        } else {
            let width: CGFloat

            // sometimes item width will be too large and overflow row, causing undesirable
            // layout, probably due to floating point errors. Just floor and can live with
            // the extra item spacing.

            switch layout.layoutType {
            case .columns:
                let itemWidth = itemWidth(columns: layout.layoutValue)
                width = floor(itemWidth.width)
                columns = itemWidth.columns
            case .minWidth:
                let itemWidth = itemWidth(minWidth: layout.layoutValue)
                width = floor(itemWidth.width)
                columns = itemWidth.columns
            }

            itemSize = singleItemSize(width: width)
            return itemSize
        }
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

            reachedTop = minIndexPath <= rows * columns - 1
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

            reachedBottom = maxIndexPath >= currentElementIDHashes.count - columns * rows
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

    private func singleItemSize(width: CGFloat) -> CGSize {

        guard !data.isEmpty else { return .init(width: width, height: 0) }

        let view: AnyView = if width > 0 {
            AnyView(viewProvider(data[0], .init(column: -1, row: -1)).frame(width: width))
        } else {
            AnyView(viewProvider(data[0], .init(column: -1, row: -1)))
        }

        let singleItem = UIHostingController(rootView: view)
        singleItem.view.sizeToFit()
        // sizeToFit will sometimes round up, need to account for in CollectionHStack?
        let changeRatio = width / singleItem.view.bounds.size.width
        return singleItem.view.bounds.size * changeRatio
    }

    // MARK: item width

    /// Precondition: columns > 0
    private func itemWidth(columns: CGFloat, trailingInset: CGFloat = 0) -> (width: CGFloat, columns: Int) {

        precondition(columns > 0, "Given `columns` is less than or equal to 0")

        let itemSpaces: CGFloat
        let sectionInsets: CGFloat

        if floor(columns) == columns {
            itemSpaces = columns - 1
            sectionInsets = collectionView.flowLayout.sectionInset.horizontal
        } else {
            itemSpaces = floor(columns)
            sectionInsets = collectionView.flowLayout.sectionInset.left
        }

        let itemSpacing = itemSpaces * collectionView.flowLayout.minimumInteritemSpacing
        let totalNegative = sectionInsets + itemSpacing + trailingInset

        return ((collectionView.frame.width - totalNegative) / columns, Int(columns))
    }

    /// Precondition: minWidth > 0
    private func itemWidth(minWidth: CGFloat) -> (width: CGFloat, columns: Int) {

        precondition(minWidth > 0, "Given `minWidth` is less than or equal to 0")

        // Ensure that each item has a given minimum width
        let layout = collectionView.flowLayout
        var columns = CGFloat(Int((collectionView.frame.width - layout.sectionInset.horizontal) / minWidth))

        guard columns != 1 else { return itemWidth(columns: 1) }

        let preItemSpacing = (columns - 1) * layout.minimumInteritemSpacing

        let totalNegative = layout.sectionInset.horizontal + preItemSpacing

        // if adding negative space with current column count would result in column sizes < minWidth
        if columns * minWidth + totalNegative > bounds.width {
            columns -= 1
        }

        return itemWidth(columns: columns)
    }
}
