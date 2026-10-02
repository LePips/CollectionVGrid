import Combine
import SwiftUI

struct ItemRemeasurementView<Content: View, Trigger: Publisher>: View where Trigger.Failure == Never {

    @State
    private var measurement = ItemMeasurementRevision()

    let publisher: Trigger
    let content: (Int) -> Content

    var body: some View {
        ItemRemeasurementContent(measurement: measurement, content: content)
            .onReceive(publisher) { _ in
                // Keep received events when SwiftUI replaces the publisher.
                DispatchQueue.main.async {
                    measurement.value &+= 1
                }
            }
    }
}

private final class ItemMeasurementRevision: ObservableObject {

    @Published
    var value = 0
}

/// Observe revisions separately to avoid resubscribing to completed publishers.
private struct ItemRemeasurementContent<Content: View>: View {

    @ObservedObject
    var measurement: ItemMeasurementRevision

    let content: (Int) -> Content

    var body: some View {
        content(measurement.value)
    }
}
