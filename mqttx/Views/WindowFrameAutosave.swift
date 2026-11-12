import SwiftUI
import AppKit

extension View {
    /// Persists position and size of the hosting window under `name`
    /// (stored in UserDefaults by AppKit and restored on the next launch).
    func windowFrameAutosave(_ name: String) -> some View {
        background(WindowFrameAutosaveView(name: name))
    }
}

private struct WindowFrameAutosaveView: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> AutosaveView {
        AutosaveView(name: name)
    }

    func updateNSView(_ nsView: AutosaveView, context: Context) {}

    final class AutosaveView: NSView {
        private let name: String
        private var configuredWindow: NSWindow?

        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window
            // AppKit allows one window per autosave name; further windows keep the
            // default (cascaded) placement.
            if NSApp.windows.contains(where: { $0 !== window && $0.frameAutosaveName == name }) { return }
            // Defer so SwiftUI has finished its own initial sizing before we restore.
            DispatchQueue.main.async { [name] in
                window.setFrameUsingName(name)
                window.setFrameAutosaveName(name)
            }
        }
    }
}
