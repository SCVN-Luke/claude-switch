import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let dir = GuideExporter.outputDir else { return }
            GuideExporter.run(to: dir)
            exit(0)
        }
    }
}

@main
struct ClaudeSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // Export mode only renders the Guide, so the model must not touch disk, Keychain or Claude.
    @StateObject private var model = AppModel(preview: GuideExporter.outputDir != nil)

    var body: some Scene {
        MenuBarExtra("Claude Switch", systemImage: "person.2.circle") {
            MenuView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Switch", id: "manage") {
            ManageWindow().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}
