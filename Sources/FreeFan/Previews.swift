import SwiftUI
import FreeFanCore
import FreeFanSMC

/// Xcode canvas harness. Everything it touches is a throwaway store in the temporary directory, so previewing never
/// reads or writes the real settings or presets, and the helper is not involved.
private struct PopoverPreview: NSViewControllerRepresentable {
    var temperature: Float = 46.5
    var rpm: Float = 2900

    func makeNSViewController(context: Context) -> PopoverViewController {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("freefan-previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let controller = PopoverViewController(
            store: PresetStore(url: directory.appendingPathComponent("presets.json")),
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
        controller.update(Self.snapshot(temperature: temperature, rpm: rpm))
        return controller
    }

    func updateNSViewController(_ controller: PopoverViewController, context: Context) {
        controller.update(Self.snapshot(temperature: temperature, rpm: rpm))
    }

    private static func snapshot(temperature: Float, rpm: Float) -> LiveSnapshot {
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
