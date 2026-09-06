import SwiftUI

@main
struct VigilApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}
