#if os(iOS)
import DifferenceKit
import SwiftUI

public class UICollectionVList<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>:
    UIView,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout
    where Data.Element == Element, Data.Index == Int
{

    private var _id: KeyPath<Element, ID>

    private var items: [CollectionItem<Element, ID>]
    private var data: Data
    private var deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?
    private var deleteActionTitle: String
    private var headerProvider: () -> any View
    private var headerSize: CGSize!
    private var itemSize: CGSize!
    private var viewProvider: (Element, CollectionVGridLocation) -> Content

    public init(
        id: KeyPath<Element, ID>,
        data: Data,
        deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?,
        deleteActionTitle: String,
        headerProvider: @escaping () -> any View,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> Content
    ) {
        self._id = id
        self.items = data.map { CollectionItem(element: $0, id: $0[keyPath: id]) }
        self.data = data
        self.deleteActionProvider = deleteActionProvider
        self.deleteActionTitle = deleteActionTitle
        self.headerProvider = headerProvider
        self.viewProvider = viewProvider

        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {

        func makeHeaderSection(environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.showsSeparators = false

            return NSCollectionLayoutSection.list(
                using: config,
                layoutEnvironment: environment
            )
        }

        func makeContentSection(environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {

            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false

            if let deleteActionProvider {
                config.trailingSwipeActionsConfigurationProvider = { context in

                    let deleteAction = UIContextualAction(style: .destructive, title: self.deleteActionTitle) { _, _, completionHandler in

                        let item = self.items[context.row].element
                        deleteActionProvider(item, .init(column: 0, row: context.row))

                        completionHandler(true)
                    }
                    deleteAction.backgroundColor = .systemRed
                    deleteAction.image = UIImage(systemName: "trash.fill")

                    let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
                    configuration.performsFirstActionWithFullSwipe = true
                    return configuration
                }
            }

            return NSCollectionLayoutSection.list(
                using: config,
                layoutEnvironment: environment
            )
        }

        return UICollectionViewCompositionalLayout { sectionIndex, environment -> NSCollectionLayoutSection? in
            if sectionIndex == 0 {
                makeHeaderSection(environment: environment)
            } else {
                makeContentSection(environment: environment)
            }
        }
    }

    private lazy var collectionView: UICollectionView = {

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(
            HostingCollectionViewCell<AnyView>.self,
            forCellWithReuseIdentifier: cellReuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = nil
//        collectionView.showsVerticalScrollIndicator = scrollIndicatorsVisible

        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        return collectionView
    }()

    override public func layoutSubviews() {
        super.layoutSubviews()

        itemSize = nil
        collectionView.performBatchUpdates {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: update

    func update(
        data newData: Data,
        isScrollEnabled: Bool,
        verticalScrollIndicatorVisibility: ScrollIndicatorVisibility
    ) {

        // data

        let newItems = newData.map { CollectionItem(element: $0, id: $0[keyPath: _id]) }
        let changed = items.map(\.differenceIdentifier) != newItems.map(\.differenceIdentifier)
        items = newItems
        data = newData
        if changed {
            collectionView.reloadData()
        }

        collectionView.isScrollEnabled = isScrollEnabled
        collectionView.verticalScrollIndicatorVisibility = verticalScrollIndicatorVisibility
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        2
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        if section == 0 {
            1
        } else {
            items.count
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: cellReuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell<AnyView>

        if indexPath.section == 0 {
            cell.setup(view: AnyView(headerProvider()))
        } else {
            let item = items[indexPath.row].element
            let location = CollectionVGridLocation(column: 0, row: indexPath.row)
            cell.setup(view: AnyView(viewProvider(item, location)), id: AnyHashable(items[indexPath.row].id))
        }

        return cell
    }
}
#endif
