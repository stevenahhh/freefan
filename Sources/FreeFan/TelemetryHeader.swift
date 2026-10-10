import AppKit
import SwiftUI
import FreeFanSMC

struct HeaderReadout: Equatable {
    struct Fan: Equatable {
        var index: Int
        var rpm: Float?
        var maxRPM: Float?

        /// Percent of the fan's maximum speed, so a stopped fan reads 0 % and a fan at Mn does not read 0 %.
        var percent: Float? {
            guard let rpm, let maxRPM, maxRPM > 0 else { return nil }
            return min(max(rpm / maxRPM * 100, 0), 100)
        }
    }

    var cpu: Float?
    var gpu: Float?
    var battery: Float?
    var fanRows: [[Fan?]] = []

    private static let fansPerRow = 3

    init() {}

    init(reading: SensorReading?, fans info: [FanInfo]) {
        cpu = reading?.cpu
        gpu = reading?.gpu
        battery = reading?.battery
        let fans = info.map { limit in
            Fan(index: limit.index,
                rpm: reading?.fans.first { $0.index == limit.index }?.rpm,
                maxRPM: limit.maxRPM)
        }
        fanRows = stride(from: 0, to: fans.count, by: Self.fansPerRow).map { start in
            let row = Array(fans[start..<min(start + Self.fansPerRow, fans.count)])
            return row + Array(repeating: nil, count: Self.fansPerRow - row.count)
        }
    }
}

final class HeaderModel: ObservableObject {
    @Published var readout = HeaderReadout()
    @Published var showsRPM = false
    var onUnitsChanged: ((Bool) -> Void)?

    func setShowsRPM(_ value: Bool) {
        guard value != showsRPM else { return }
        showsRPM = value
        onUnitsChanged?(value)
    }
}

private struct Stat: Identifiable {
    var id: String
    var value: String
    var caption: String
}

struct HeaderContent: View {
    @ObservedObject var model: HeaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(temperatures)
            ForEach(Array(model.readout.fanRows.enumerated()), id: \.offset) { _, fans in
                Button {
                    model.setShowsRPM(!model.showsRPM)
                } label: {
                    row(fans.map(fanStat) + [Stat(id: "empty", value: "", caption: "")])
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.showsRPM ? "Show fan speed as a percentage of full speed" : "Show fan speed in rpm")
            }
        }
        .animation(.snappy, value: model.readout)
        .animation(.snappy, value: model.showsRPM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var temperatures: [Stat] {
        [
            Stat(id: "cpu", value: Self.degrees(model.readout.cpu), caption: "CPU"),
            Stat(id: "gpu", value: Self.degrees(model.readout.gpu), caption: "GPU"),
            Stat(id: "bat", value: Self.degrees(model.readout.battery), caption: "BATTERY"),
        ]
    }

    private func fanStat(_ fan: HeaderReadout.Fan?) -> Stat {
        guard let fan else { return Stat(id: "empty", value: "", caption: "") }
        let value: String
        if let rpm = fan.rpm {
            value = model.showsRPM ? String(Int(rpm.rounded())) : "\(Int((fan.percent ?? 0).rounded()))%"
        } else {
            value = "--"
        }
        return Stat(id: "fan\(fan.index)", value: value, caption: "FAN \(fan.index)")
    }

    private func row(_ stats: [Stat]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 0) {
                    Text(stat.value)
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                    Text(stat.caption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func degrees(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))\u{00B0}"
    }
}
