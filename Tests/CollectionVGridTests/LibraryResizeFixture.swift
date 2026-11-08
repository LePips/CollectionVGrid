#if os(iOS) || os(macOS)
@testable import CollectionVGrid
import SwiftUI

@MainActor
@Observable
final class LibraryFixtureState {
    var padding: CGFloat = 0
    var topInset: CGFloat = 100
    @ObservationIgnored
    var locations: [Int: CollectionVGridLocation] = [:]
    /// Content requested to measure an item, which happens outside the grid.
    @ObservationIgnored
    var measurements = 0
    /// Content requested for a cell.
    @ObservationIgnored
    var cellConfigurations = 0
}

struct GridResizeReport {
    let drift: [CGFloat]
    let frames: Int
    let measurements: Int
    let cellConfigurations: Int

    var maximumAnchorDrift: CGFloat {
        drift.max() ?? 0
    }
}

// MARK: - Views

struct LibraryItem: Identifiable {
    let id: Int
}

/// Mirrors a paging library: animated horizontal padding outside, and a geometry
/// reader that supplies the grid's layout and insets from its current size.
struct LibraryFixtureRoot: View {
    let state: LibraryFixtureState
    private let items: [LibraryItem]

    init(state: LibraryFixtureState, itemCount: Int) {
        self.state = state
        items = (0 ..< itemCount).map(LibraryItem.init)
    }

    var body: some View {
        GeometryReader { outer in
            GeometryReader { geometry in
                let compact = geometry.size.width < 600
                CollectionVGrid(
                    uniqueElements: items,
                    layout: .minWidth(
                        compact ? 160 : 200,
                        insets: EdgeInsets(top: state.topInset, leading: 10, bottom: 34, trailing: 10),
                        itemSpacing: 10,
                        lineSpacing: 10
                    )
                ) { item, location in
                    // Like an adaptive library, content depends on the current size,
                    // so the parent updates the grid on every resize frame.
                    card(item, location: location, width: geometry.size.width)
                }
                #if canImport(UIKit)
                .contentInsetAdjustmentBehavior(.never)
                #endif
            }
            .padding(.leading, state.padding)
            .frame(width: outer.size.width, height: outer.size.height)
            .animation(.smooth(duration: 0.35), value: state.padding)
        }
        .ignoresSafeArea()
    }

    private func card(_ item: LibraryItem, location: CollectionVGridLocation, width: CGFloat) -> LibraryCard {
        if location.column >= 0 {
            state.locations[item.id] = location
            state.cellConfigurations += 1
        } else {
            state.measurements += 1
        }
        return LibraryCard(index: item.id) { _ = (location, width) }
    }
}

/// Shaped like a media poster button: artwork with overlays, a matched transition
/// source, hover and context menu effects, geometry tracking, and an action closure,
/// which makes every re-render evaluate the card's body.
struct LibraryCard: View {
    @Namespace
    private var namespace
    @State
    private var size: CGSize = .zero

    let index: Int
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill").padding(4)
                    }
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.white)
                            .frame(width: max(0, size.width * 0.4), height: 4)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    #if os(iOS)
                    .contentShape(.contextMenuPreview, Rectangle())
                    .matchedTransitionSource(id: "item", in: namespace)
                    #endif
                    .shadow(radius: 2)
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif
                Text("Title \(index)").font(.footnote).lineLimit(1)
                Text("2024 · Drama").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Play", systemImage: "play.fill") {}
            Button("Mark Played", systemImage: "checkmark") {}
        }
    }
}
#endif
