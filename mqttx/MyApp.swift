import SwiftUI

@main
struct MyApp: App {
    /// Saved connections are shared by all windows.
    @State private var store = ConnectionStore()

    var body: some Scene {
        // Every window (⌘N) gets its own MQTT connection.
        WindowGroup("mqttX", id: "main") {
            WindowRoot()
                .environment(store)
                .frame(minWidth: 900, minHeight: 560)
                .windowFrameAutosave("MainWindow")
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }
        }
    }
}

/// Owns the per-window connection service.
private struct WindowRoot: View {
    @State private var service = MQTTClientService()

    var body: some View {
        ContentView()
            .environment(service)
            .onDisappear { service.disconnect() }
    }
}

private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Neues Fenster") { openWindow(id: "main") }
            .keyboardShortcut("n")
    }
}
