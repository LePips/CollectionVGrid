#if canImport(UIKit)
import UIKit

extension UICollectionView {

    func apply<ID: Hashable>(
        _ changes: CollectionDiff<ID>,
        setData: (CollectionSnapshot<ID>) -> Void
    ) {
        guard window != nil else {
            setData(changes.target)
            reloadData()
            return
        }

        if changes.isEmpty {
            setData(changes.target)
            return
        }

        for stage in changes {
            performBatchUpdates {
                // Publish the count and identity mapping synchronously for each
                // stage. Move sources are relative to the post-deletion stage.
                setData(stage.data)

                if !stage.deleted.isEmpty {
                    deleteItems(at: stage.deleted.map { IndexPath(item: $0, section: 0) })
                }
                if !stage.inserted.isEmpty {
                    insertItems(at: stage.inserted.map { IndexPath(item: $0, section: 0) })
                }
                for move in stage.moved {
                    moveItem(
                        at: IndexPath(item: move.source, section: 0),
                        to: IndexPath(item: move.target, section: 0)
                    )
                }
            }
        }
    }
}
#endif
