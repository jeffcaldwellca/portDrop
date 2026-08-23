import SwiftUI

@main
struct PortDropApp: App {
    var body: some Scene {
        MenuBarExtra("PortDrop", systemImage: "network") {
            Text("Hello")
        }
        .menuBarExtraStyle(.window)
    }
}
