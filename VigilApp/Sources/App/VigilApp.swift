import SwiftUI

@main
struct VigilApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flushPendingWrites() }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}
