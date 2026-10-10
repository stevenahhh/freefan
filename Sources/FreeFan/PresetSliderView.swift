import AppKit
import FreeFanCore

final class PresetSliderView: NSView {
    var onSelect: ((String) -> Void)?
    var onNew: (() -> Void)?

    private static let chipHeight: CGFloat = 24
    private static let spacing: CGFloat = 3
    private static let maxChipWidth: CGFloat = 150

    private let fixedWidth: CGFloat
    private let scrollView = SliderScrollView()
    private let content = FlippedView()
    private let indicator = FlippedView()
    private let newButton = NSButton()
    private var chips: [NSButton] = []
    private var signature = ""

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedWidth, height: Self.chipHeight)
    }

    init(width: CGFloat) {
        fixedWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.chipHeight))

        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 6
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = content
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New preset")
        newButton.imagePosition = .imageOnly
        newButton.isBordered = false
        newButton.bezelStyle = .regularSquare
        newButton.setButtonType(.momentaryChange)
        newButton.contentTintColor = .secondaryLabelColor
        newButton.toolTip = "New preset from the current curve"
        newButton.target = self
        newButton.action = #selector(newTapped(_:))
        newButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(newButton)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            newButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 6),
            newButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            newButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newButton.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func reload(library: PresetLibrary) {
        let newSignature = library.presets.map { "\($0.id)\u{1F}\($0.name)" }.joined(separator: "\u{1E}")
        if newSignature != signature {
            signature = newSignature
            rebuild(library: library)
        }
        select(active: library.active, animated: false)
    }

    /// Vertical wheel and trackpad deltas move the row, so a mouse works without a horizontal gesture.
    private final class SliderScrollView: NSScrollView {
        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
                return super.scrollWheel(with: event)
            }
            let clip = contentView
            let limit = max((documentView?.frame.width ?? 0) - clip.bounds.width, 0)
            guard limit > 0 else { return super.scrollWheel(with: event) }
            // A wheel notch down walks towards the later presets, like a vertical list would.
            let x = min(max(clip.bounds.origin.x + event.scrollingDeltaY, 0), limit)
            guard x != clip.bounds.origin.x else { return super.scrollWheel(with: event) }
            clip.scroll(to: NSPoint(x: x, y: 0))
            reflectScrolledClipView(clip)
        }
    }

    private func rebuild(library: PresetLibrary) {
        chips.forEach { $0.removeFromSuperview() }
        content.subviews.forEach { $0.removeFromSuperview() }
        chips = [makeChip(title: "Auto", id: PresetLibrary.autoID)]
        chips += library.presets.map { makeChip(title: $0.name, id: $0.id) }
        content.addSubview(indicator)
        chips.forEach(content.addSubview)
        arrange()
    }

    private func makeChip(title: String, id: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(chipClicked(_:)))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.lineBreakMode = .byTruncatingTail
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.toolTip = id == PresetLibrary.autoID ? "Let macOS control the fans" : nil
        return button
    }

    private func arrange() {
        var x: CGFloat = 0
        for chip in chips {
            let width = min(ceil(chip.fittingSize.width) + 14, Self.maxChipWidth)
            chip.frame = NSRect(x: x, y: 0, width: width, height: Self.chipHeight)
            x += width + Self.spacing
        }
        content.frame = NSRect(x: 0, y: 0, width: max(x - Self.spacing, 1), height: Self.chipHeight)
    }

    private func select(active: String, animated: Bool) {
        var selected: NSRect?
        for chip in chips {
            let isSelected = chip.identifier?.rawValue == active
            chip.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
            chip.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .medium)
            if isSelected { selected = chip.frame }
        }
        guard let frame = selected else { return }
        let target = frame.insetBy(dx: -2, dy: 0)
        guard animated, !indicator.frame.isEmpty else {
            indicator.frame = target
            content.scrollToVisible(frame.insetBy(dx: -20, dy: 0))
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            indicator.animator().frame = target
            content.animator().scrollToVisible(frame.insetBy(dx: -20, dy: 0))
        }
    }

    @objc private func chipClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        select(active: id, animated: true)
        onSelect?(id)
    }

    @objc private func newTapped(_ sender: Any?) {
        onNew?()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
