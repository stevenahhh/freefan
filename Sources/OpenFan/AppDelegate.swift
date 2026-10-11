import AppKit
import OpenFanCore
import OpenFanSMC
import OpenFanUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PresetStore()
    private let settingsStore = SettingsStore()
    private let helper = HelperClient()
    private let installer = HelperInstaller()

    private let smcQueue = DispatchQueue(label: "com.stevenahhh.openfan.smc", qos: .utility)
    private var smc: SMC?
    private var telemetry: Telemetry?

    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel?
    private var panelController: PopoverViewController?
    private var timer: DispatchSourceTimer?

    private var latestReading: SensorReading?
    private var latestFans: [FanInfo] = []
    private var latestPressure: MemoryPressure?
    private var pressureMonitor: MemoryPressureMonitor?
    private var helperMessage: String?
    private var lastTitle = ""
    private var shownPressure: MemoryPressure?
    private var shownAppearance: NSAppearance.Name?
    private var dotImages: [MemoryPressure: NSImage] = [:]
    private var currentInterval: TimeInterval = 0

    /// The helper drops control after 12 s of silence, so a running curve is pinged at least twice within that.
    private static let heartbeatInterval: TimeInterval = 5

    /// What the panel shows; the fans' target speeds are not on it.
    private static let panelSensors: SensorSet = [.cpu, .gpu, .battery, .fans]

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
            button.action = #selector(togglePanel(_:))
        }
        lastTitle = "--"

        latestPressure = MemoryPressure.read()
        pressureMonitor = MemoryPressureMonitor { [weak self] level in
            guard let self else { return }
            self.latestPressure = level
            self.refreshStatusItem()
            self.panelController?.update(self.snapshot())
        }
        refreshStatusItem()
        startTimer()

        smcQueue.async { [weak self] in
            guard let self else { return }
            do {
                let smc = try SMC()
                self.smc = smc
                self.telemetry = try Telemetry(smc: smc)
            } catch {
                NSLog("OpenFan: SMC unavailable: \(error)")
            }
        }

        helper.connect()
        applyActivePreset()
    }

    /// An accessory app has no Edit menu, and without one the text fields ignore cmd-C, cmd-V, cmd-X and cmd-A.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let quitItem = app.addItem(withTitle: "Quit OpenFan", action: #selector(quitOpenFan(_:)), keyEquivalent: "q")
        quitItem.target = self
        appItem.submenu = app
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

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        updateTimer()
    }

    private var menuBarSensors: SensorSet {
        MenuBarTemplate.sensors(in: settingsStore.settings.menuBarTemplate)
    }

    /// How often there is something to do: an open panel wants fresh readings every second, the menu bar text its
    /// sensors every three, a running curve its heartbeat every five. With none of those the app has no timer at all
    /// (0), and memory pressure reaches it by notification.
    private func desiredInterval() -> TimeInterval {
        if panel?.isVisible == true { return 1 }
        if !menuBarSensors.isEmpty { return 3 }
        return store.library.activePreset == nil ? 0 : Self.heartbeatInterval
    }

    private func updateTimer() {
        guard let timer else { return }
        let interval = desiredInterval()
        guard interval != currentInterval else { return }
        currentInterval = interval
        if interval == 0 {
            timer.schedule(deadline: .distantFuture)
        } else {
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 200)))
        }
    }

    private func tick() {
        let isOpen = panel?.isVisible == true
        let sensors = isOpen ? Self.panelSensors : menuBarSensors
        guard isOpen || !sensors.isEmpty else {
            helper.keepAlive()
            return
        }
        smcQueue.async { [weak self] in
            guard let self else { return }
            let reading = self.telemetry?.read(sensors)
            let fans = self.telemetry?.fans ?? []
            if isOpen { _ = self.helper.refreshStatus() }
            self.helper.keepAlive()
            DispatchQueue.main.async {
                self.apply(reading: reading, fans: fans)
            }
        }
    }

    /// A full reading and the helper's status, taken synchronously (a millisecond or two) so a panel that was closed,
    /// and so not being refreshed, opens with current numbers instead of rolling in from nothing.
    private func refreshNow() {
        let (reading, fans) = smcQueue.sync { (telemetry?.read(Self.panelSensors), telemetry?.fans ?? []) }
        latestReading = reading
        latestFans = fans
        _ = helper.refreshStatus()
    }

    private func apply(reading: SensorReading?, fans: [FanInfo]) {
        latestReading = reading
        latestFans = fans

        refreshStatusItem()
        panelController?.update(snapshot())
    }

    /// Recomputes the title and the dot from the latest readings and the settings, and touches the button only when
    /// something it shows has changed.
    private func refreshStatusItem() {
        let settings = settingsStore.settings
        let values = MenuBarValues(reading: latestReading, presetName: store.library.activePreset?.name ?? "Auto")
        let title = latestReading == nil && !menuBarSensors.isEmpty ? "--" : MenuBarTemplate.render(settings.menuBarTemplate, values)
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

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            panel.dismiss()
            return
        }
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let controller = PopoverViewController(store: store, settings: settingsStore, actions: panelActions())
        let panel = MenuBarPanel(content: controller.view)
        controller.onPreferredSizeChange = { [weak panel] size in panel?.resize(to: size) }
        panel.onDismiss = { [weak self] in self?.panelDidDismiss() }
        self.panel = panel
        panelController = controller
        refreshNow()
        controller.update(snapshot())
        button.highlight(true)
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.present(size: controller.preferredContentSize, below: anchor, on: buttonWindow.screen)
        updateTimer()
    }

    /// The panel and its controller are dropped with it, so a closed panel leaves nothing behind in memory.
    private func panelDidDismiss() {
        statusItem.button?.highlight(false)
        panel = nil
        panelController = nil
        updateTimer()
    }

    private func panelActions() -> PopoverActions {
        PopoverActions(
            presetsChanged: { [weak self] in
                self?.applyActivePreset()
                self?.refreshStatusItem()
                self?.updateTimer()
            },
            settingsChanged: { [weak self] in
                self?.refreshStatusItem()
                self?.updateTimer()
            },
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
        panelController?.update(snapshot())
    }

    @objc private func quitOpenFan(_ sender: Any?) {
        quit()
    }

    private func quit() {
        timer?.cancel()
        timer = nil
        helper.shutdown()
        NSApp.terminate(nil)
    }

    private func dotImage(for level: MemoryPressure) -> NSImage {
        if let cached = dotImages[level] { return cached }
        let image = level.dotImage()
        image.isTemplate = false
        dotImages[level] = image
        return image
    }

    private func applyStatusContent(title: String, pressure: MemoryPressure?) {
        guard let button = statusItem.button else { return }
        guard let pressure else {
            button.image = title.isEmpty ? Self.fallbackSymbol : nil
            button.title = title
            return
        }
        button.image = dotImage(for: pressure)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: Self.menuBarTextColor(for: button.effectiveAppearance),
        ])
    }

    /// Shown when there is neither text nor a dot, so the item can still be clicked.
    private static let fallbackSymbol: NSImage? = {
        let image = NSImage(systemSymbolName: "fan", accessibilityDescription: "OpenFan")
        image?.isTemplate = true
        return image
    }()

    /// A button holding a full-color image is drawn without the menu bar's vibrancy, so its text needs an explicit
    /// color that follows the bar's light or dark appearance.
    private static func menuBarTextColor(for appearance: NSAppearance) -> NSColor {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark ? .white : .black
    }
}
