import AppKit
import FreeFanCore
import FreeFanSMC

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = PresetStore()
    private let helper = HelperClient()
    private let installer = HelperInstaller()

    private let smcQueue = DispatchQueue(label: "com.stevenahhh.freefan.smc", qos: .utility)
    private var smc: SMC?
    private var telemetry: Telemetry?

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: DispatchSourceTimer?

    private var latestReading: SensorReading?
    private var latestFans: [FanInfo] = []
    private var lastTitle = ""
    private var menuOpen = false
    private var currentInterval: TimeInterval = 0
    private var shownPressure: MemoryPressure?
    private var dotImages: [MemoryPressure: NSImage] = [:]
    private var shownAppearance: NSAppearance.Name?

    private var editor: CurveEditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = try? store.load()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "--"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.imagePosition = .imageLeft
        }
        lastTitle = "--"
        menu.delegate = self
        statusItem.menu = menu

        startTelemetry()

        // One SMC + Telemetry pair, created once off the main thread.
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

    private func startTelemetry() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        updateInterval(force: true)
        timer.resume()
    }

    private func updateInterval(force: Bool = false) {
        guard let timer else { return }
        let interval: TimeInterval = (menuOpen || isEditorOpen) ? 1.0 : 3.0
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

        let title = Self.title(for: reading)
        let appearance = statusItem.button?.effectiveAppearance.name
        if title != lastTitle || pressure != shownPressure || appearance != shownAppearance {
            lastTitle = title
            shownPressure = pressure
            shownAppearance = appearance
            applyStatusContent(title: title, pressure: pressure)
            statusItem.button?.toolTip = pressure.map { "Memory pressure: \($0.label)" }
        }

        if let editor, !editor.isOpen {
            self.editor = nil
            updateInterval()
        }
        if let editor, editor.isOpen {
            let peak = reading?.fans.compactMap { $0.rpm }.max()
            editor.updateLive(
                temperature: reading?.input(.max),
                actualRPM: peak,
                fanMaxRPM: maxRPM(forHighestFanIn: reading)
            )
        }
    }

    private func maxRPM(forHighestFanIn reading: SensorReading?) -> Float? {
        guard let reading else { return nil }
        let fan = reading.fans.filter { $0.rpm != nil }.max { ($0.rpm ?? 0) < ($1.rpm ?? 0) }
        guard let fan else { return nil }
        return latestFans.first { $0.index == fan.index }?.maxRPM
    }

    /// Fixed sRGB colors: dynamic system colors resolve to monochrome in the menu bar's vibrant appearance.
    private static func dotColor(for level: MemoryPressure) -> NSColor {
        switch level {
        case .normal: return NSColor(srgbRed: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        case .warning: return NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        case .critical: return NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)
        }
    }

    private func dotImage(for level: MemoryPressure) -> NSImage {
        if let cached = dotImages[level] { return cached }
        let color = Self.dotColor(for: level)
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

    private static func title(for reading: SensorReading?) -> String {
        guard let reading else { return "--" }
        let temperature: String
        if let value = reading.input(.max) {
            temperature = "\(Int(value.rounded()))\u{00B0}"
        } else {
            temperature = "--"
        }
        let rpm: String
        if let peak = reading.fans.compactMap({ $0.rpm }).max() {
            rpm = peak >= 1000 ? String(format: "%.1fk", Double(peak) / 1000) : "\(Int(peak.rounded()))"
        } else {
            rpm = "--"
        }
        return "\(temperature) \(rpm)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        rebuildMenu()
        updateInterval()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        updateInterval()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let reading = latestReading
        menu.addItem(infoItem("CPU \(Self.temperatureText(reading?.cpu))"))
        menu.addItem(infoItem("GPU \(Self.temperatureText(reading?.gpu))"))
        for fan in reading?.fans ?? [] {
            let limits = latestFans.first { $0.index == fan.index }
            let range = limits.map { "[\(Int($0.minRPM.rounded()))-\(Int($0.maxRPM.rounded()))]" } ?? ""
            menu.addItem(infoItem("Fan \(fan.index): \(Self.rpmText(fan.rpm)) RPM \(range)"))
        }
        menu.addItem(infoItem("Mode: \(modeText())"))
        menu.addItem(.separator())

        let active = store.library.active
        menu.addItem(selectionItem(title: "Auto", id: PresetLibrary.autoID, checked: active == PresetLibrary.autoID))
        for preset in store.library.presets {
            menu.addItem(selectionItem(title: preset.name, id: preset.id, checked: active == preset.id))
        }
        menu.addItem(.separator())

        menu.addItem(actionItem(title: "Edit Curves\u{2026}", action: #selector(editCurves)))
        if installer.isInstalled {
            menu.addItem(actionItem(title: "Uninstall Helper\u{2026}", action: #selector(uninstallHelper)))
        } else {
            menu.addItem(actionItem(title: "Install Helper\u{2026}", action: #selector(installHelper)))
        }
        menu.addItem(actionItem(title: "Quit FreeFan", action: #selector(quit), keyEquivalent: "q"))
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func selectionItem(title: String, id: String, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.state = checked ? .on : .off
        return item
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func modeText() -> String {
        if !installer.isInstalled { return "Helper not installed" }
        if store.library.active == PresetLibrary.autoID { return "Auto" }
        return store.library.activePreset?.name ?? "Auto"
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        try? store.setActive(id)
        applyActivePreset()
    }

    private func applyActivePreset() {
        if let preset = store.library.activePreset {
            helper.setCurve(preset)
        } else {
            helper.setAuto()
        }
    }

    @objc private func editCurves() {
        if let editor, !editor.isOpen {
            self.editor = nil
        }
        if editor == nil {
            editor = CurveEditorWindowController(store: store) { [weak self] in
                self?.applyActivePreset()
            }
        }
        editor?.show()
        updateInterval()
    }

    private var isEditorOpen: Bool { editor?.isOpen ?? false }

    @objc private func installHelper() {
        installer.install { [weak self] status, message in
            self?.finishHelperAction(success: status == 0, message: message)
        }
    }

    @objc private func uninstallHelper() {
        installer.uninstall { [weak self] status, message in
            self?.finishHelperAction(success: status == 0, message: message)
        }
    }

    private func finishHelperAction(success: Bool, message: String) {
        if !success {
            let alert = NSAlert()
            alert.messageText = "FreeFan"
            alert.informativeText = message.lowercased().contains("cancel") ? "Cancelled." : (message.isEmpty ? "Unavailable." : message)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        if menuOpen { rebuildMenu() }
    }

    @objc private func quit() {
        timer?.cancel()
        timer = nil
        helper.shutdown()
        NSApp.terminate(nil)
    }

    private static func temperatureText(_ value: Float?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f\u{00B0}C", value)
    }

    private static func rpmText(_ value: Float?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }
}
