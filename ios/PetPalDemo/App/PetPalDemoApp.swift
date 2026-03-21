import SwiftUI

@main
struct PetPalDemoApp: App {
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appStore)
        }
    }
}
