import SwiftUI

@main
struct MundialStreamsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(width: 360)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
