import SwiftUI
import FreeFanCore
import FreeFanSMC

/// A reading that makes every part of the popover show something: two fans at the given rpm, three temperatures.
public func previewSnapshot(temperature: Float = 46.5, rpm: Float = 2900) -> LiveSnapshot {
    let fans = [
        FanInfo(index: 0, minRPM: 2317, maxRPM: 7826),
        FanInfo(index: 1, minRPM: 2317, maxRPM: 7826),
    ]
    let reading = SensorReading(
        cpu: temperature,
        gpu: temperature - 3,
        battery: 33,
        fans: [
            FanReading(index: 0, rpm: rpm, targetRPM: rpm, manual: true),
            FanReading(index: 1, rpm: rpm - 12, targetRPM: rpm, manual: true),
        ]
    )
    return LiveSnapshot(
        reading: reading,
        fans: fans,
        pressure: .normal,
        helperInstalled: true,
        helperConnected: true,
        helperStatus: HelperStatus(mode: .curve, inputTemperature: Double(temperature), targetRPM: [rpm, rpm]),
        helperError: nil
    )
}

/// A popover wired to a throwaway store, for the canvas and the preview host. Nothing it does can reach the real
/// settings or presets, and the helper is not involved. A built-in preset is active so the graph, the live readout
/// and the editor buttons are all on screen.
public func previewPopover() -> PopoverViewController {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("freefan-previews", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let store = PresetStore(url: directory.appendingPathComponent("presets.json"))
    try? store.load()
    try? store.setActive("balanced")

    let controller = PopoverViewController(
        store: store,
        settings: SettingsStore(url: directory.appendingPathComponent("settings.json")),
        actions: PopoverActions(
            presetsChanged: {},
            settingsChanged: {},
            installHelper: {},
            uninstallHelper: {},
            quit: {}
        )
    )
    controller.loadView()
    controller.update(previewSnapshot())
    return controller
}

/// Xcode canvas harness. The previews run with the Xcode toolchain, since #Preview expands through macro plugins
/// that do not ship with the Command Line Tools.
private struct PopoverPreview: NSViewControllerRepresentable {
    var temperature: Float = 46.5
    var rpm: Float = 2900

    func makeNSViewController(context: Context) -> PopoverViewController {
        let controller = previewPopover()
        controller.update(previewSnapshot(temperature: temperature, rpm: rpm))
        return controller
    }

    func updateNSViewController(_ controller: PopoverViewController, context: Context) {
        controller.update(previewSnapshot(temperature: temperature, rpm: rpm))
    }
}

#Preview("Popover") {
    PopoverPreview()
        .frame(width: 380)
}

#Preview("Popover - light") {
    PopoverPreview(temperature: 71.5, rpm: 5200)
        .frame(width: 380)
        .preferredColorScheme(.light)
}

#Preview("Popover - dark") {
    PopoverPreview(temperature: 71.5, rpm: 5200)
        .frame(width: 380)
        .preferredColorScheme(.dark)
}
