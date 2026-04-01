import SwiftUI

// MARK: - App Entry Point

@main
struct ZoomNukeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: Layout.windowWidth, height: Layout.windowHeight)
                .preferredColorScheme(.dark)
        }
    }
}
