import SwiftUI

@main
struct CollectionVGridExampleApp: App {
    var body: some Scene {
        WindowGroup("CollectionVGrid") {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 680, minHeight: 480)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 720)
        #endif
    }
}
