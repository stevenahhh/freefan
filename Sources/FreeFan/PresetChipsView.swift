import AppKit
import FreeFanCore

final class PresetChipsView: NSView {
    var onSelect: ((String) -> Void)?
    var onNew: (() -> Void)?

    private static let spacing: CGFloat = 6
    private static let maxChipWidth: CGFloat = 150
    private static let newID = "\u{0}new"

    private let fixedWidth: CGFloat
    private var buttons: [NSButton] = []
    private var layoutSignature = ""
    private var contentHeight: CGFloat = 22

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedWidth, height: contentHeight)
    }

    init(width: CGFloat) {
        fixedWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func reload(library: PresetLibrary) {
        let signature = library.presets.map { "\($0.id)\u{1F}\($0.name)" }.joined(separator: "\u{1E}")
        if signature != layoutSignature {
            layoutSignature = signature
            buttons.forEach { $0.removeFromSuperview() }
            buttons = [makeChip(title: "Auto", id: PresetLibrary.autoID)]
            buttons += library.presets.map { makeChip(title: $0.name, id: $0.id) }
            let new = makeChip(title: "+", id: Self.newID)
            new.toolTip = "New preset from the current curve"
            buttons.append(new)
            buttons.forEach(addSubview)
            contentHeight = arrange()
            invalidateIntrinsicContentSize()
        }
        for button in buttons {
            let id = button.identifier?.rawValue
            button.state = id == library.active ? .on : .off
        }
    }

    private func makeChip(title: String, id: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(chipClicked(_:)))
        button.bezelStyle = .recessed
        button.setButtonType(.pushOnPushOff)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12)
        button.lineBreakMode = .byTruncatingTail
        button.identifier = NSUserInterfaceItemIdentifier(id)
        return button
    }

    private func arrange() -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for button in buttons {
            let size = button.fittingSize
            let width = min(size.width, Self.maxChipWidth)
            if x > 0, x + width > fixedWidth {
                x = 0
                y += rowHeight + Self.spacing
                rowHeight = 0
            }
            button.frame = NSRect(x: x, y: y, width: width, height: size.height)
            x += width + Self.spacing
            rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }

    @objc private func chipClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if id == Self.newID {
            onNew?()
        } else {
            onSelect?(id)
        }
    }
}
