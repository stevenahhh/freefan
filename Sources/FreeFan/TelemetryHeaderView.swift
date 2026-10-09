import AppKit
import FreeFanCore
import FreeFanSMC

private final class StatView: NSStackView {
    private let valueLabel = NSTextField(labelWithString: "--")

    init(caption: String) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        addArrangedSubview(valueLabel)
        addArrangedSubview(captionLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func set(_ text: String) {
        if valueLabel.stringValue != text { valueLabel.stringValue = text }
    }
}

final class TelemetryHeaderView: NSView {
    private let cpu = StatView(caption: "CPU")
    private let gpu = StatView(caption: "GPU")
    private let battery = StatView(caption: "BATTERY")
    private let fans = NSTextField(labelWithString: "")
    private let pressure = NSTextField(labelWithString: "")
    private let mode = NSTextField(wrappingLabelWithString: "")
    private var pressureDrawn = false
    private var drawnPressure: MemoryPressure?

    init(width: CGFloat) {
        super.init(frame: .zero)

        fans.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        fans.textColor = .secondaryLabelColor
        pressure.font = .systemFont(ofSize: 11)
        mode.font = .systemFont(ofSize: 11)
        mode.textColor = .secondaryLabelColor
        mode.preferredMaxLayoutWidth = width

        let stats = NSStackView(views: [cpu, gpu, battery])
        stats.orientation = .horizontal
        stats.distribution = .fillEqually
        stats.alignment = .top

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let detail = NSStackView(views: [fans, spacer, pressure])
        detail.orientation = .horizontal
        detail.alignment = .centerY

        let column = NSStackView(views: [stats, detail, mode])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            stats.widthAnchor.constraint(equalToConstant: width),
            detail.widthAnchor.constraint(equalToConstant: width),
            mode.widthAnchor.constraint(equalToConstant: width),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ snapshot: LiveSnapshot, mode text: String, isWarning: Bool) {
        cpu.set(Self.degrees(snapshot.reading?.cpu))
        gpu.set(Self.degrees(snapshot.reading?.gpu))
        battery.set(Self.degrees(snapshot.reading?.battery))

        let fanText = (snapshot.reading?.fans ?? [])
            .map { "Fan \($0.index)  \($0.rpm.map { String(Int($0.rounded())) } ?? "--") rpm" }
            .joined(separator: "     ")
        if fans.stringValue != fanText { fans.stringValue = fanText }

        if mode.stringValue != text { mode.stringValue = text }
        mode.textColor = isWarning ? .systemOrange : .secondaryLabelColor

        if !pressureDrawn || snapshot.pressure != drawnPressure {
            pressureDrawn = true
            drawnPressure = snapshot.pressure
            if let level = snapshot.pressure {
                let font = NSFont.systemFont(ofSize: 11)
                let text = NSMutableAttributedString(
                    string: "\u{25CF} ",
                    attributes: [.foregroundColor: level.dotColor, .font: font]
                )
                text.append(NSAttributedString(
                    string: "Memory \(level.label)",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]
                ))
                pressure.attributedStringValue = text
            } else {
                pressure.stringValue = ""
            }
        }
    }

    private static func degrees(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))\u{00B0}"
    }
}
