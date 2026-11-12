import SwiftUI

/// Switches between the connection setup and the topic browser.
struct ContentView: View {
    @Environment(MQTTClientService.self) private var service

    var body: some View {
        if service.profile != nil && service.state != .disconnected {
            TopicBrowserView()
        } else {
            ConnectionManagerView()
        }
    }
}

#Preview {
    ContentView()
        .environment(ConnectionStore())
        .environment(MQTTClientService())
}
