import AppKit
import OpenFanCore
import OpenFanUI

/// Hosts the popover with sample data in a plain window: a preview path that needs neither the canvas, the menu bar
/// item nor the helper, and that the Xcode View Debugger can attach to.
final class PreviewHost: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = previewPopover()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: controller.preferredContentSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFan preview"
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let host = PreviewHost()
application.delegate = host
application.setActivationPolicy(.regular)
application.run()
