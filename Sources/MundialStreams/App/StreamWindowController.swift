import AppKit
import SwiftUI

@MainActor
final class StreamWindowController: NSObject, NSWindowDelegate {
    private let session: StreamSession
    private var window: NSWindow?
    var onClose: (() -> Void)?

    init(session: StreamSession) {
        self.session = session
        super.init()

        let rootView = PlayerWindowView(session: session)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = session.item.name
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.center()
        window.delegate = self
        self.window = window
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        window = nil
    }
}
