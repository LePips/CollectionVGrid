import SwiftUI

/// Native hosting roots do not inherit the representable's SwiftUI environment.
/// Use the same values for measurement and display, including custom client keys.
struct EnvironmentAwareContent<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues?

    var body: some View {
        if let environment {
            content.environment(\.self, environment)
        } else {
            content
        }
    }
}

/// Capture the sizing inputs eagerly while the representable is updating. Stored
/// EnvironmentValues retain SwiftUI's tracked values; reading an old environment
/// later does not provide an immutable snapshot for invalidation comparisons.
/// Custom sizing inputs are forwarded too, and invalidate via `remeasureItems(on:)`.
struct ContentMeasurementEnvironment: Equatable {
    let dynamicTypeSize: DynamicTypeSize
    let font: Font?
    let locale: Locale
    let calendar: Calendar
    let timeZone: TimeZone
    let layoutDirection: LayoutDirection
    let displayScale: CGFloat
    let lineLimit: Int?
    let lineSpacing: CGFloat
    let minimumScaleFactor: CGFloat
    let allowsTightening: Bool
    let multilineTextAlignment: TextAlignment
    let truncationMode: Text.TruncationMode
    let legibilityWeight: LegibilityWeight?
    let controlSize: ControlSize
    let isEnabled: Bool
    #if canImport(UIKit)
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    #endif

    init(_ environment: EnvironmentValues) {
        dynamicTypeSize = environment.dynamicTypeSize
        font = environment.font
        locale = environment.locale
        calendar = environment.calendar
        timeZone = environment.timeZone
        layoutDirection = environment.layoutDirection
        displayScale = environment.displayScale
        lineLimit = environment.lineLimit
        lineSpacing = environment.lineSpacing
        minimumScaleFactor = environment.minimumScaleFactor
        allowsTightening = environment.allowsTightening
        multilineTextAlignment = environment.multilineTextAlignment
        truncationMode = environment.truncationMode
        legibilityWeight = environment.legibilityWeight
        controlSize = environment.controlSize
        isEnabled = environment.isEnabled
        #if canImport(UIKit)
        horizontalSizeClass = environment.horizontalSizeClass
        verticalSizeClass = environment.verticalSizeClass
        #endif
    }
}
