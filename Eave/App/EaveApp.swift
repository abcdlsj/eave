import AppKit
import SwiftUI

@main
struct EaveApp: App {
    @NSApplicationDelegateAdaptor(EaveAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Eave runs as a pure LSUIElement menu bar utility; Settings is hosted on demand via AppCoordinator.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class EaveAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid spawning live UI/status items when hosted inside the unit test runner.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            coordinator?.handleIncomingURL(url)
        }
    }
}
