import SwiftUI

@main
struct ClaudeSwitchApp: App {
    @StateObject private var model = AppModel()

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
