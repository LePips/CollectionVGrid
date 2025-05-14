import DifferenceKit
import SwiftUI

#if !os(tvOS)
public class UICollectionVList<Element, Data: Collection, ID: Hashable>:
    UIView,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout
    where Data.Element == Element, Data.Index == Int
{
    
    private var _id: KeyPath<Element, ID>
    
    private var currentElementIDHashes: [Int]
    private var data: Data
    private var deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?
    private var deleteActionTitle: String
    private var headerProvider: () -> any View
    private var headerSize: CGSize!
    private var itemSize: CGSize!
    private var scrollIndicatorsVisible: Bool
    private var viewProvider: (Element, CollectionVGridLocation) -> any View
    
    public init(
        id: KeyPath<Element, ID>,
        data: Data,
        deleteActionProvider: ((Element, CollectionVGridLocation) -> Void)?,
        deleteActionTitle: String,
        headerProvider: @escaping () -> any View,
        scrollIndicatorsVisible: Bool,
        viewProvider: @escaping (Element, CollectionVGridLocation) -> any View
    ) {
        self._id = id
        self.currentElementIDHashes = []
        self.data = data
        self.deleteActionProvider = deleteActionProvider
        self.deleteActionTitle = deleteActionTitle
        self.headerProvider = headerProvider
        self.scrollIndicatorsVisible = scrollIndicatorsVisible
        self.viewProvider = viewProvider
        
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        
        func makeHeaderSection(environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.showsSeparators = false
            
            let section = NSCollectionLayoutSection.list(
                using: config,
                layoutEnvironment: environment
            )

            return section
        }

        func makeContentSection(environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            
            if let deleteActionProvider {
                config.trailingSwipeActionsConfigurationProvider = { context in
                    
                    let deleteAction = UIContextualAction(style: .destructive, title: self.deleteActionTitle) { action, _, completionHandler in
                        
                        let item = self.data[context.row]
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
            
            let section = NSCollectionLayoutSection.list(
                using: config,
                layoutEnvironment: environment
            )

            return section
        }
        
        return UICollectionViewCompositionalLayout { (sectionIndex, environment) -> NSCollectionLayoutSection? in
            if sectionIndex == 0 {
                return makeHeaderSection(environment: environment)
            } else {
                return makeContentSection(environment: environment)
            }
        }
    }
    
    private lazy var collectionView: UICollectionView = {

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
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
    
    override public func layoutSubviews() {
        super.layoutSubviews()

        itemSize = nil
        update(data: data)

        collectionView.performBatchUpdates {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }
    
    // MARK: update

    // TODO: this seems to be called a lot when nothing changes
    func update(
        data newData: Data
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

            // TODO: Fix if necessary? See comment at top of UICollectionVGrid.swift.

//            collectionView.reload(using: changes) { _ in
//                self.currentElementIDHashes = newHashes
//            }

            currentElementIDHashes = newIDs
            collectionView.reloadData()
        }
    }
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    public func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        if section == 0 {
            return 1
        } else {
            return currentElementIDHashes.count
        }
    }
    
    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HostingCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell
        
        if indexPath.section == 0 {
            cell.setupHostingView(with: headerProvider())
        } else {
            let item = data[indexPath.row]
            let location = CollectionVGridLocation(column: indexPath.row, row: indexPath.row)
            cell.setupHostingView(with: viewProvider(item, location))
        }
        
        return cell
    }
}
#endif
