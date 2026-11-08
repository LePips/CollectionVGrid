#if os(macOS)
import AppKit
@testable import CollectionVGrid
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct MacOSResizeParityTests {
    @Test
    func `adaptive window resizing bounds refresh work and delivers final locations`() async throws {
        let fixture = LibraryFixture(itemCount: 10000)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        let widths = Array(stride(from: CGFloat(1180), through: 390, by: -10))
        let report = fixture.recordLiveResize(widths: widths + widths.reversed())
        #expect(report.maximumAnchorDrift < 1)
        #expect(report.measurements <= report.frames)
        #expect(report.cellConfigurations * 2 < report.frames * fixture.visibleCellCount)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.visibleLocationsAreCurrent())
    }

    @Test
    func `repeated proposals preserve the anchor and a new scroll replaces it`() async throws {
        let fixture = LibraryFixture(itemCount: 10000)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        let widths: [CGFloat] = (0 ..< 120).map { $0.isMultiple(of: 2) ? 860 : 1180 }
        #expect(fixture.recordLiveResize(widths: widths).maximumAnchorDrift < 1)
        fixture.scroll(toItem: 180)
        let boundaries: [CGFloat] = [639.75, 640, 640.25, 849.75, 850, 850.25, 1059.75, 1060, 1060.25]
        #expect(fixture.recordLiveResize(widths: (0 ..< 6).flatMap { _ in boundaries }).maximumAnchorDrift < 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.visibleLocationsAreCurrent())
    }

    @Test
    func `vertical inset updates reuse width measurements`() async throws {
        let fixture = LibraryFixture()
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        let report = fixture.recordFrames(values: [90, 80, 60, 50, 70, 100]) { fixture.state.topInset = $0 }
        #expect(report.measurements == 0)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.visibleLocationsAreCurrent())
    }

    @Test
    func `AppKit hosting preserves state on resize and resets it on identity reuse`() async throws {
        _ = NSApplication.shared
        var seen: [Int] = []
        let item = HostingCollectionViewItem<StatefulContent>()
        item.view.frame = CGRect(x: 0, y: 0, width: 180, height: 140)
        item.configure(StatefulContent(seed: 1) { seen.append($0) }, id: 10)
        let window = NSWindow(contentRect: item.view.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = item.view
        window.orderBack(nil)
        defer { window.close() }
        func settle() async throws {
            item.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            item.view.layoutSubtreeIfNeeded()
        }
        try await settle()
        let host = try #require(item.view.subviews.first)
        #expect(seen.last == 1)
        item.configure(StatefulContent(seed: 99) { seen.append($0) }, id: 10)
        for width: CGFloat in [310.5, 220, 250] {
            item.view.frame.size.width = width
            try await settle()
            #expect(abs(host.frame.width - item.view.bounds.width) <= 0.5 / window.backingScaleFactor)
            #expect(host.frame.height == item.view.bounds.height)
            #expect(seen.last == 1)
        }
        item.prepareForReuse()
        item.configure(StatefulContent(seed: 2) { seen.append($0) }, id: 20)
        try await settle()
        #expect(item.view.subviews.first === host)
        #expect(seen.last == 2)
    }
}

private struct StatefulContent: View {
    @State
    private var value: Int
    var report: (Int) -> Void

    init(seed: Int, report: @escaping (Int) -> Void) {
        _value = State(initialValue: seed)
        self.report = report
    }

    var body: some View {
        report(value)
        return Color.blue.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
