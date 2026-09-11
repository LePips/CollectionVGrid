#if os(iOS)
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionVGridRefreshTests {
    private typealias Grid = CollectionVGrid<Int, [Int], Int, Text>
    private typealias NativeGrid = UICollectionVGrid<Int, [Int], Int, Text>

    private func makeGrid() -> NativeGrid {
        NativeGrid(
            id: \.self, data: [], layout: .columns(2),
            onReachedBottomEdge: {}, onReachedBottomEdgeOffset: .offset(0),
            onReachedTopEdge: {}, onReachedTopEdgeOffset: .offset(0), proxy: nil
        ) { value, _ in Text("\(value)") }
    }

    private func configuration() -> Grid {
        Grid(count: 0, layout: .columns(2)) { Text("\($0)") }
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { findCollection(in: $0) }.first
    }

    private func makeWindow(containing view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        return window
    }

    private func sendRefreshEvent(to control: UIRefreshControl) throws {
        // Swift package tests have no UIApplication to dispatch UIControl events.
        // Invoke the registered target/action directly to exercise the same wiring.
        let target = try #require(control.allTargets.first as? NSObject)
        let action = try #require(control.actions(forTarget: target, forControlEvent: .valueChanged)?.first)
        target.perform(NSSelectorFromString(action), with: control)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test
    func emptyGridRefreshWaitsForCompletionAndIgnoresDuplicatePulls() async throws {
        let view = makeGrid()
        let gate = RefreshGate()
        var calls = 0
        let original = configuration()
        let configured = original.onRefresh {
            calls += 1
            await gate.wait()
        }.onReachedBottomEdge {} // The modifier preserves CollectionVGrid's type.
        #expect(original.refreshAction == nil)
        view.configure(configured)
        let window = makeWindow(containing: view)
        defer { window.isHidden = true }
        let collection = try #require(findCollection(in: view))
        let control = try #require(collection.refreshControl)
        #expect(collection.alwaysBounceVertical)
        #expect(collection.numberOfItems(inSection: 0) == 0)
        control.beginRefreshing()
        try sendRefreshEvent(to: control)
        try sendRefreshEvent(to: control)
        try await waitUntil { gate.isWaiting }
        #expect(calls == 1)
        #expect(control.isRefreshing)
        gate.resume()
        try await waitUntil { !control.isRefreshing }

        var updatedCalls = 0
        view.configure(configuration().onRefresh { updatedCalls += 1 })
        #expect(collection.refreshControl === control)
        control.beginRefreshing()
        try sendRefreshEvent(to: control)
        try await waitUntil { updatedCalls == 1 && !control.isRefreshing }
        #expect(calls == 1)
    }

    @Test
    func disablingRefreshCancelsAndOldCompletionCannotStopNewRefresh() async throws {
        let view = makeGrid()
        let oldGate = RefreshGate()
        var oldWasCancelled = false
        view.configure(configuration().onRefresh {
            await oldGate.wait() // Deliberately finish after cancellation.
            oldWasCancelled = Task.isCancelled
        })
        let window = makeWindow(containing: view)
        defer { window.isHidden = true }
        let collection = try #require(findCollection(in: view))
        let oldControl = try #require(collection.refreshControl)
        oldControl.beginRefreshing()
        try sendRefreshEvent(to: oldControl)
        try await waitUntil { oldGate.isWaiting }

        view.configure(configuration().onRefresh(action: nil))
        #expect(collection.refreshControl == nil)
        #expect(!oldControl.isRefreshing)

        let newGate = RefreshGate()
        view.configure(configuration().onRefresh { await newGate.wait() })
        let newControl = try #require(collection.refreshControl)
        #expect(newControl !== oldControl)
        newControl.beginRefreshing()
        try sendRefreshEvent(to: newControl)
        try await waitUntil { newGate.isWaiting }
        oldGate.resume()
        try await waitUntil { oldWasCancelled }
        #expect(newControl.isRefreshing)
        newGate.resume()
        try await waitUntil { !newControl.isRefreshing }
    }

    @Test
    func dismantlingCancelsRefreshAndTaskDoesNotRetainGrid() async throws {
        var view: NativeGrid? = makeGrid()
        weak var weakView = view
        let gate = RefreshGate()
        var wasCancelled = false
        view?.configure(configuration().onRefresh {
            await gate.wait()
            wasCancelled = Task.isCancelled
        })
        let window = makeWindow(containing: try #require(view))
        defer { window.isHidden = true }
        let control = try #require(view.flatMap { findCollection(in: $0) }?.refreshControl)
        control.beginRefreshing()
        try sendRefreshEvent(to: control)
        try await waitUntil { gate.isWaiting }
        Grid.dismantleUIView(try #require(view), coordinator: ())
        #expect(!control.isRefreshing)
        view?.removeFromSuperview()
        view = nil
        try await waitUntil { weakView == nil }
        gate.resume()
        try await waitUntil { wasCancelled }
    }

    @Test
    func hostedCustomActionUpdatesSwiftUIDataWithoutDeadlocking() async throws {
        let model = RefreshModel()
        let host = UIHostingController(rootView: RefreshFixture(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let collection = try #require(findCollection(in: host.view))
        let control = try #require(collection.refreshControl)
        #expect(collection.numberOfItems(inSection: 0) == 0)
        control.beginRefreshing()
        try sendRefreshEvent(to: control)
        try await waitUntil { model.gate.isWaiting }
        try await waitUntil { collection.numberOfItems(inSection: 0) == 4 }
        #expect(control.isRefreshing)
        model.gate.resume()
        try await waitUntil { !control.isRefreshing }
        model.enabled = false
        try await waitUntil { collection.refreshControl == nil }
    }
}

@MainActor
private final class RefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class RefreshModel: ObservableObject {
    @Published var count = 0
    @Published var enabled = true
    let gate = RefreshGate()
}

private struct RefreshFixture: View {
    @ObservedObject var model: RefreshModel

    private var refreshAction: (@MainActor () async -> Void)? {
        guard model.enabled else { return nil }
        return {
            model.count = 4
            await model.gate.wait()
        }
    }

    var body: some View {
        CollectionVGrid(count: model.count, layout: .columns(2)) {
            Text("\($0)").frame(height: 40)
        }
        .onRefresh(action: refreshAction)
    }
}
#endif
