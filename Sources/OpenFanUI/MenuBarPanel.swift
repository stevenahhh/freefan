import AppKit
import OpenFanCore

/// A borderless panel that opens just under the status item on the system's Liquid Glass (a blurred material before
/// macOS 26) and closes on a click anywhere else, on Escape and when the app loses the foreground. It follows the size
/// of the view it holds, keeping its top edge where it is.
public final class MenuBarPanel: NSPanel {
    public var onDismiss: (() -> Void)?

    static let cornerRadius: CGFloat = 20
    private static let resizeDuration: TimeInterval = 0.2

    private var clickMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?

    public init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        contentView = Self.makeBackground(hosting: content)
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    /// `anchor` is the status item's frame in screen coordinates.
    public func present(size: NSSize, below anchor: NSRect, on screen: NSScreen?) {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        setFrame(PanelPlacement.frame(size: size, anchor: anchor, visible: visible), display: false)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(nil)
        watchForDismissal()
    }

    public func resize(to size: NSSize) {
        let target = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        guard isVisible else {
            setFrame(target, display: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeDuration
            animator().setFrame(target, display: true)
        }
    }

    public func dismiss() {
        guard isVisible else { return }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        clickMonitor = nil
        deactivationObserver = nil
        orderOut(nil)
        onDismiss?()
    }

    /// Only while the panel is open: a click in another app, on the desktop or on another menu bar item never reaches
    /// this app's own views, so a global monitor is the only way to see it. The app has no monitor when the panel is closed.
    private func watchForDismissal() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    static func makeBackground(hosting content: NSView) -> NSView {
        // NSGlassEffectView only exists in the macOS 26 SDK, which ships with Swift 6.2; an older toolchain builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return glassBackground(hosting: content)
        }
        #endif
        return materialBackground(hosting: content)
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    static func glassBackground(hosting content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }
    #endif

    static func materialBackground(hosting content: NSView) -> NSView {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = roundedMask(radius: cornerRadius)
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
