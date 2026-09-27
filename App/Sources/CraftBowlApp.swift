import SwiftUI

@main
struct CraftBowlApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
