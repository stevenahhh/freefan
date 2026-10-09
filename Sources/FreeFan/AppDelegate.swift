import AppKit
import FreeFanCore
import FreeFanSMC

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = PresetStore()
    private let settingsStore = SettingsStore()
    private let helper = HelperClient()
    private let installer = HelperInstaller()

    private let smcQueue = DispatchQueue(label: "com.stevenahhh.freefan.smc", qos: .utility)
    private var smc: SMC?
    private var telemetry: Telemetry?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var popoverController: PopoverViewController?
    private var timer: DispatchSourceTimer?

    private var latestReading: SensorReading?
    private var latestFans: [FanInfo] = []
    private var latestPressure: MemoryPressure?
    private var helperMessage: String?
    private var lastTitle = ""
    private var shownPressure: MemoryPressure?
    private var shownAppearance: NSAppearance.Name?
    private var dotImages: [MemoryPressure: NSImage] = [:]
    private var currentInterval: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = try? store.load()
        settingsStore.load()
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "--"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        lastTitle = "--"

        startTelemetry()

        smcQueue.async { [weak self] in
            guard let self else { return }
            do {
                let smc = try SMC()
                self.smc = smc
                self.telemetry = try Telemetry(smc: smc)
            } catch {
                NSLog("FreeFan: SMC unavailable: \(error)")
            }
        }

        helper.connect()
        applyActivePreset()
    }

    /// An accessory app has no Edit menu, and without one the text fields ignore cmd-C, cmd-V, cmd-X and cmd-A.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func startTelemetry() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        updateInterval(force: true)
        timer.resume()
    }

    private func updateInterval(force: Bool = false) {
        guard let timer else { return }
        let interval: TimeInterval = popover?.isShown == true ? 1.0 : 3.0
        if !force && interval == currentInterval { return }
        currentInterval = interval
        let leeway = DispatchTimeInterval.milliseconds(Int(interval * 1000 * 0.2))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
    }

    private func tick() {
        smcQueue.async { [weak self] in
            guard let self else { return }
            let reading = self.telemetry?.read()
            let fans = self.telemetry?.fans ?? []
            let pressure = MemoryPressure.read()
            _ = self.helper.refreshStatus()
            if self.helper.isControlling {
                self.helper.keepAlive()
            }
            DispatchQueue.main.async {
                self.apply(reading: reading, fans: fans, pressure: pressure)
            }
        }
    }

    private func apply(reading: SensorReading?, fans: [FanInfo], pressure: MemoryPressure?) {
        latestReading = reading
        latestFans = fans
        latestPressure = pressure

        refreshStatusItem()
        popoverController?.update(snapshot())
    }

    /// Recomputes the title and the dot from the latest readings and the settings, and touches the button only when
    /// something it shows has changed.
    private func refreshStatusItem() {
        let settings = settingsStore.settings
        let values = MenuBarValues(reading: latestReading, presetName: store.library.activePreset?.name ?? "Auto")
        let title = latestReading == nil ? "--" : MenuBarTemplate.render(settings.menuBarTemplate, values)
        let dot = settings.showPressureDot ? latestPressure : nil
        let appearance = statusItem.button?.effectiveAppearance.name
        guard title != lastTitle || dot != shownPressure || appearance != shownAppearance else { return }
        lastTitle = title
        shownPressure = dot
        shownAppearance = appearance
        applyStatusContent(title: title, pressure: dot)
        statusItem.button?.toolTip = dot.map { "Memory pressure: \($0.label)" }
    }

    private func snapshot() -> LiveSnapshot {
        LiveSnapshot(
            reading: latestReading,
            fans: latestFans,
            pressure: latestPressure,
            helperInstalled: installer.isInstalled,
            helperConnected: helper.isConnected,
            helperStatus: helper.lastStatus,
            helperError: helper.lastError ?? helperMessage
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        let controller = PopoverViewController(store: store, settings: settingsStore, actions: popoverActions())
        popoverController = controller
        let popover = NSPopover()
        controller.onPreferredSizeChange = { [weak popover] size in popover?.contentSize = size }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        self.popover = popover
        _ = controller.view
        controller.update(snapshot())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        updateInterval()
    }

    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil
        popover = nil
        popoverController = nil
        updateInterval()
    }

    private func popoverActions() -> PopoverActions {
        PopoverActions(
            presetsChanged: { [weak self] in
                self?.applyActivePreset()
                self?.refreshStatusItem()
            },
            settingsChanged: { [weak self] in self?.refreshStatusItem() },
            installHelper: { [weak self] in self?.runHelperAction(install: true) },
            uninstallHelper: { [weak self] in self?.runHelperAction(install: false) },
            quit: { [weak self] in self?.quit() }
        )
    }

    private func applyActivePreset() {
        if let preset = store.library.activePreset {
            helper.setCurve(preset)
        } else {
            helper.setAuto()
        }
    }

    private func runHelperAction(install: Bool) {
        let finish: (Int32, String) -> Void = { [weak self] status, message in
            self?.finishHelperAction(status: status, message: message)
        }
        if install {
            installer.install(completion: finish)
        } else {
            installer.uninstall(completion: finish)
        }
    }

    private func finishHelperAction(status: Int32, message: String) {
        if status == 0 {
            helperMessage = nil
            helper.reconnect()
            applyActivePreset()
        } else if message.lowercased().contains("cancel") {
            helperMessage = "Cancelled."
        } else {
            helperMessage = message.isEmpty ? "Helper change failed." : message
        }
        popoverController?.update(snapshot())
    }

    private func quit() {
        timer?.cancel()
        timer = nil
        helper.shutdown()
        NSApp.terminate(nil)
    }

    private func dotImage(for level: MemoryPressure) -> NSImage {
        if let cached = dotImages[level] { return cached }
        let color = level.dotColor
        let image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        dotImages[level] = image
        return image
    }

    private func applyStatusContent(title: String, pressure: MemoryPressure?) {
        guard let button = statusItem.button else { return }
        guard let pressure else {
            button.image = nil
            button.title = title
            return
        }
        button.image = dotImage(for: pressure)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: Self.menuBarTextColor(for: button.effectiveAppearance),
        ])
    }

    /// A button holding a full-color image is drawn without the menu bar's vibrancy, so its text needs an explicit
    /// color that follows the bar's light or dark appearance.
    private static func menuBarTextColor(for appearance: NSAppearance) -> NSColor {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark ? .white : .black
    }
}
