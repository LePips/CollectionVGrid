import Foundation

/// Both native grids defer rebuilding visible SwiftUI content while geometry is
/// changing. New cells use the latest generation immediately; retained cells
/// catch up once resizing settles. At most one callback is queued per grid.
@MainActor
final class CollectionContentRefresh {
    private(set) var generation = 0
    private var needsRefresh = false
    private var isScheduled = false
    private var lastGeometryChange: TimeInterval = -.infinity
    private let settleDelay: TimeInterval = 0.1

    func invalidate() {
        generation &+= 1
        needsRefresh = true
    }

    func geometryChanged() {
        lastGeometryChange = ProcessInfo.processInfo.systemUptime
    }

    func didRefresh() {
        needsRefresh = false
    }

    func refreshIfSettled(isAttached: Bool, refresh: @escaping @MainActor () -> Void) {
        guard needsRefresh else { return }

        let remaining = lastGeometryChange + settleDelay - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, isAttached else {
            needsRefresh = false
            refresh()
            return
        }
        guard !isScheduled else { return }

        isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self else { return }

            self.isScheduled = false
            self.refreshIfSettled(isAttached: isAttached, refresh: refresh)
        }
    }
}
