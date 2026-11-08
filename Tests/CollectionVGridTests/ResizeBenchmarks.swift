#if os(iOS) || os(macOS)
@testable import CollectionVGrid
import Darwin
import QuartzCore
import SwiftUI
import Testing

/// Opt in with COLLECTION_RESIZE_BENCHMARK=1. Timing is diagnostic, while geometry,
/// virtualization, and measurement bounds are checked independently of machine speed.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["COLLECTION_RESIZE_BENCHMARK"] == "1"))
@MainActor
struct ResizeBenchmarks {
    private var variant: String {
        ProcessInfo.processInfo.environment["BENCHMARK_VARIANT"] ?? "patched"
    }

    private var requiresCorrectGeometry: Bool {
        variant != "baseline" || ProcessInfo.processInfo.environment["BENCHMARK_REQUIRE_BASELINE_GEOMETRY"] == "1"
    }

    private var layoutOnly: Bool {
        #if os(macOS)
        ProcessInfo.processInfo.environment["BENCHMARK_APPKIT_LAYOUT_ONLY"] == "1"
        #else
        false
        #endif
    }

    @Test(arguments: [600, 10000, 100_000])
    func `continuous resize`(itemCount: Int) async throws {
        let step: CGFloat = itemCount == 100_000 ? -12 : -4
        let sweep = Array(stride(from: CGFloat(1180), through: 390, by: step))
        try await benchmark("continuous", itemCount: itemCount, widths: sweep + sweep.reversed())
    }

    @Test
    func `repeated proposals`() async throws {
        try await benchmark("cached-proposals", itemCount: 10000, widths: (0 ..< 600).map { $0.isMultiple(of: 2) ? 860 : 1180 })
    }

    @Test
    func `paced repeated proposals`() async throws {
        try await benchmark("paced-proposals", itemCount: 10000, widths: (0 ..< 300).map { $0.isMultiple(of: 2) ? 860 : 1180 }, paced: true)
    }

    @Test
    func `fractional column boundaries`() async throws {
        // Minimum width 200, horizontal insets 20, gaps 10: four columns fit at 850.
        let boundaries: [CGFloat] = [639.75, 640, 640.25, 849.75, 850, 850.25, 1059.75, 1060, 1060.25]
        try await benchmark("fractional-boundaries", itemCount: 10000, widths: (0 ..< 60).flatMap { _ in boundaries })
    }

    @Test
    func `animated sidebar soak`() async throws {
        let fixture = LibraryFixture(itemCount: 10000)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        #if os(macOS)
        try await fixture.waitForPresentation()
        #endif
        let monitor = ResizeDisplayMonitor()
        #if os(macOS)
        if !layoutOnly {
            monitor.start(view: fixture.host)
        }
        #else
        monitor.start()
        #endif
        defer { monitor.stop() }
        var drift: CGFloat = 0
        var maxError: CGFloat = 0
        var maxVisible = 0
        let measurements = fixture.state.measurements
        let configurations = fixture.state.cellConfigurations
        let initialRSS = residentMB()
        let started = CACurrentMediaTime()
        for cycle in 0 ..< 24 {
            let report = try await fixture.recordAnimation {
                fixture.state.padding = cycle.isMultiple(of: 2) ? 320 : 0
            }
            drift = max(drift, report.maximumAnchorDrift)
            maxVisible = max(maxVisible, fixture.visibleCellCount)
            maxError = try max(maxError, sizingError(fixture))
        }
        monitor.stop()
        #if os(macOS)
        if !layoutOnly {
            #expect(!monitor.intervals.isEmpty, "A native animation comparison requires display callbacks")
        }
        #endif
        emit([
            "scenario": layoutOnly ? "sidebar-updates" : "animated-sidebar", "items": 10000, "cycles": 24,
            "elapsed_ms": (CACurrentMediaTime() - started) * 1000,
            "display_samples_available": !monitor.intervals.isEmpty,
            "display_callbacks": monitor.intervals.count,
            "callback_p95_ms": percentile(monitor.intervals, 0.95),
            "late_callbacks": monitor.lateCallbacks,
            "measurements": fixture.state.measurements - measurements,
            "cell_configurations": fixture.state.cellConfigurations - configurations,
            "max_visible": maxVisible, "anchor_drift_pt": drift, "height_error_pt": maxError,
            "rss_start_mb": initialRSS, "rss_end_mb": residentMB(),
        ])
        if requiresCorrectGeometry {
            #expect(drift < 1)
        }
        #expect(maxVisible > 0 && maxVisible < 100)
        // The grid intentionally refreshes locations after geometry settles.
        // Animation completion and its delayed refresh can land on different
        // run-loop turns. Bound that wait outside the recorded animation time.
        for _ in 0 ..< 25 {
            if fixture.visibleLocationsAreCurrent() {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let locationsAreCurrent = fixture.visibleLocationsAreCurrent()
        #expect(locationsAreCurrent)
        if requiresCorrectGeometry {
            #expect(maxError < 1)
        }
    }

    private func benchmark(_ scenario: String, itemCount: Int, widths: [CGFloat], paced: Bool = false) async throws {
        let fixture = LibraryFixture(itemCount: itemCount)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        #if os(macOS)
        try await fixture.waitForPresentation()
        #endif
        _ = fixture.recordLiveResize(widths: Array(widths.prefix(20)))
        for repetition in 0 ..< 3 {
            var durations: [Double] = []
            var cpuDurations: [Double] = []
            var offCPUDurations: [Double] = []
            var drift: CGFloat = 0
            var maxVisible = 0
            var maxError: CGFloat = 0
            let measurements = fixture.state.measurements
            let configurations = fixture.state.cellConfigurations
            let initialRSS = residentMB()
            for (index, width) in widths.enumerated() {
                let cpuStarted = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                let started = CACurrentMediaTime()
                let report = fixture.recordLiveResize(widths: [width])
                let elapsed = (CACurrentMediaTime() - started) * 1000
                let cpuElapsed = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStarted) / 1_000_000
                durations.append(elapsed)
                cpuDurations.append(cpuElapsed)
                offCPUDurations.append(max(0, elapsed - cpuElapsed))
                drift = max(drift, report.maximumAnchorDrift)
                maxVisible = max(maxVisible, fixture.visibleCellCount)
                // Oracle work stays outside the timed resize transaction.
                if index.isMultiple(of: 80) || index == widths.count - 1 {
                    maxError = try max(maxError, sizingError(fixture))
                }
                if paced {
                    // Let the run loop and rendering services drain between
                    // proposals. This wait is outside the measured transaction.
                    let remaining = 1.0 / 60 - (CACurrentMediaTime() - started)
                    if remaining > 0 {
                        try await Task.sleep(for: .seconds(remaining))
                    } else {
                        await Task.yield()
                    }
                }
            }
            #if os(macOS)
            try await fixture.waitForPresentation()
            #endif
            let measured = fixture.state.measurements - measurements
            emit([
                "scenario": scenario, "items": itemCount, "repetition": repetition,
                "frames": durations.count, "total_ms": durations.reduce(0, +),
                "p50_ms": percentile(durations, 0.5), "p95_ms": percentile(durations, 0.95),
                "p99_ms": percentile(durations, 0.99), "max_ms": durations.max() ?? 0,
                "cpu_p50_ms": percentile(cpuDurations, 0.5), "cpu_p95_ms": percentile(cpuDurations, 0.95),
                "cpu_p99_ms": percentile(cpuDurations, 0.99), "off_cpu_p95_ms": percentile(offCPUDurations, 0.95),
                "over_8_33_ms": durations.count(where: { $0 > 1000 / 120 }),
                "over_16_67_ms": durations.count(where: { $0 > 1000 / 60 }),
                "measurements": measured,
                "cell_configurations": fixture.state.cellConfigurations - configurations,
                "max_visible": maxVisible, "anchor_drift_pt": drift, "height_error_pt": maxError,
                "rss_start_mb": initialRSS, "rss_end_mb": residentMB(),
            ])
            if requiresCorrectGeometry {
                #expect(drift < 1)
            }
            #expect(maxVisible > 0 && maxVisible < 100)
            #expect(measured <= widths.count)
            if scenario == "cached-proposals" || paced {
                #expect(measured == 0)
            }
            if requiresCorrectGeometry {
                #expect(maxError < 1)
            }
            // Drain deferred refreshes between repetitions, not between resize frames.
            try await Task.sleep(for: .milliseconds(150))
            let locationsAreCurrent = fixture.visibleLocationsAreCurrent()
            #expect(locationsAreCurrent)
        }
    }

    private func sizingError(_ fixture: LibraryFixture) throws -> CGFloat {
        #if os(macOS)
        let cell = try #require(fixture.collection.visibleItems().first)
        let host = NSHostingView(rootView: LibraryCard(index: 0)
            .frame(width: cell.view.bounds.width)
            .fixedSize(horizontal: false, vertical: true))
        return abs(cell.view.bounds.height - host.fittingSize.height)
        #else
        let cell = try #require(fixture.collection.visibleCells.first)
        let host = UIHostingController(rootView: LibraryCard(index: 0)
            .frame(width: cell.bounds.width)
            .fixedSize(horizontal: false, vertical: true))
        host.safeAreaRegions = []
        let ideal = host.sizeThatFits(in: CGSize(width: cell.bounds.width, height: .greatestFiniteMagnitude))
        return abs(cell.bounds.height - ideal.height)
        #endif
    }

    private func emit(_ record: [String: Any]) {
        var record = record
        record["variant"] = variant
        #if os(macOS)
        record["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        record["platform"] = "AppKit"
        record["presentation"] = layoutOnly ? "offscreen-layout" : "visible-window"
        #else
        record["os"] = UIDevice.current.systemVersion
        record["platform"] = "UIKit"
        #endif
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("RESIZE_BENCHMARK \(String(decoding: data, as: UTF8.self))")
    }
}

private func percentile(_ samples: [Double], _ percentile: Double) -> Double {
    guard !samples.isEmpty else { return 0 }

    let sorted = samples.sorted()
    return sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * percentile)) - 1)]
}

private func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}

@MainActor
private final class ResizeDisplayMonitor: NSObject {
    private var link: CADisplayLink?
    private var previous: CFTimeInterval?
    private(set) var intervals: [Double] = []
    private(set) var lateCallbacks = 0

    #if os(macOS)
    func start(view: NSView) {
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    #else
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    #endif

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc
    private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let previous {
            let interval = now - previous
            intervals.append(interval * 1000)
            if interval > (link.targetTimestamp - link.timestamp) * 1.5 {
                lateCallbacks += 1
            }
        }
        previous = now
    }
}
#endif
