import AppKit
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

private final class HeaderColumn: NSView {
    private static let valueFont = NSFont.systemFont(ofSize: 26, weight: .semibold)
    private static let captionFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

    private let value = RollingNumberView(font: HeaderColumn.valueFont)
    private let caption = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        caption.font = Self.captionFont
        caption.textColor = .secondaryLabelColor
        for view in [value, caption] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            value.leadingAnchor.constraint(equalTo: leadingAnchor),
            value.topAnchor.constraint(equalTo: topAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.topAnchor.constraint(equalTo: value.bottomAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func set(value valueText: String, caption captionText: String) {
        value.setText(valueText, animated: true)
        if caption.stringValue != captionText { caption.stringValue = captionText }
    }

    func setPlaceholder() {
        value.setText("", animated: false)
        if !caption.stringValue.isEmpty { caption.stringValue = "" }
    }
}

private final class HeaderRow: NSView {
    private let columns = (0..<3).map { _ in HeaderColumn() }

    init() {
        super.init(frame: .zero)
        let stack = NSStackView(views: columns)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func set(_ cells: [(value: String, caption: String)]) {
        for (index, column) in columns.enumerated() {
            if index < cells.count {
                column.set(value: cells[index].value, caption: cells[index].caption)
            } else {
                column.setPlaceholder()
            }
        }
    }
}

/// The popover's top rows: CPU, GPU and battery temperatures, then one column per fan. Fan values are a percentage
/// of full speed until the fan row is clicked; the choice is handed to the owner to remember.
final class TelemetryHeaderView: NSView {
    var onUnitsChanged: ((Bool) -> Void)?

    private(set) var showsRPM = false

    private let temperatureRow = HeaderRow()
    private var fanRows: [HeaderRow] = []
    private let stack = NSStackView()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        rebuild()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ readout: HeaderReadout) {
        while fanRows.count < readout.fanRows.count {
            makeFanRow()
        }
        temperatureRow.set([
            (Self.degrees(readout.cpu), "CPU"),
            (Self.degrees(readout.gpu), "GPU"),
            (Self.degrees(readout.battery), "BATTERY"),
        ])
        for (index, row) in readout.fanRows.enumerated() where index < fanRows.count {
            fanRows[index].set(row.map(fanCell))
        }
    }

    func setShowsRPM(_ value: Bool, notify: Bool) {
        guard value != showsRPM else { return }
        showsRPM = value
        if notify { onUnitsChanged?(value) }
    }

    private func rebuild() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The fans are what the app controls, so their row sits above the temperatures.
        stack.setViews([temperatureRow], in: .top)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func makeFanRow() -> HeaderRow {
        let row = HeaderRow()
        row.toolTip = "Click to switch the fan values between a percentage and rpm"
        let click = NSClickGestureRecognizer(target: self, action: #selector(fanRowClicked(_:)))
        row.addGestureRecognizer(click)
        fanRows.append(row)
        stack.setViews(fanRows + [temperatureRow], in: .top)
        row.widthAnchor.constraint(equalTo: temperatureRow.widthAnchor).isActive = true
        return row
    }

    @objc private func fanRowClicked(_ sender: Any?) {
        showsRPM.toggle()
        onUnitsChanged?(showsRPM)
    }

    private func fanCell(_ fan: HeaderReadout.Fan?) -> (value: String, caption: String) {
        guard let fan else { return ("", "") }
        let value: String
        if let rpm = fan.rpm {
            value = showsRPM ? String(Int(rpm.rounded())) : "\(Int((fan.percent ?? 0).rounded()))%"
        } else {
            value = "--"
        }
        return (value, "FAN \(fan.index)")
    }

    private static func degrees(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))\u{00B0}"
    }
}
