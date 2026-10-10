import AppKit

final class HelpBubbleView: NSVisualEffectView {
    private static let maxTextWidth: CGFloat = 250
    private static let inset: CGFloat = 10

    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 11)
        label.preferredMaxLayoutWidth = Self.maxTextWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func setText(_ text: String) -> NSSize {
        label.stringValue = text
        let labelSize = label.sizeThatFits(NSSize(width: Self.maxTextWidth, height: .greatestFiniteMagnitude))
        return NSSize(width: ceil(labelSize.width) + Self.inset * 2, height: ceil(labelSize.height) + Self.inset * 2)
    }
}
