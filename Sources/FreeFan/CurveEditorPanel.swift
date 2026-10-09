import AppKit
import FreeFanCore
import FreeFanSMC

final class CurveEditorPanel: NSView, NSTextFieldDelegate {
    var onLibraryChange: (() -> Void)?

    var activeInput: FanControlInput? { draft?.input }

    static func title(for input: FanControlInput) -> String {
        switch input {
        case .max: return "Max (CPU or GPU)"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .battery: return "Battery (average)"
        }
    }

    private static let starterPoints = [
        CurvePoint(t: 40, p: 10),
        CurvePoint(t: 60, p: 30),
        CurvePoint(t: 80, p: 60),
        CurvePoint(t: 95, p: 100),
    ]

    private let store: PresetStore
    private let graph = CurveEditorView(frame: .zero)
    private let nameField = NSTextField(string: "")
    private let inputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(wrappingLabelWithString: "Auto: macOS controls the fans.\nPick a preset above to apply it and edit its curve here.")
    private let editorStack = NSStackView()

    private var draft: Preset?
    private var deleteArmed = false
    private var lastError: String?

    init(store: PresetStore, width: CGFloat) {
        self.store = store
        super.init(frame: .zero)
        configure(width: width)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func showActive() {
        lastError = nil
        deleteArmed = false
        draft = store.library.activePreset
        render()
    }

    func updateLive(temperature: Float?, rpm: Float?, fanMaxRPM: Float?) {
        graph.setLive(temperature: temperature, actualRPM: rpm, fanMaxRPM: fanMaxRPM)
    }

    func report(_ message: String) {
        lastError = message
        refreshLabels()
    }

    func addPreset(copying source: Preset?) {
        let preset = Preset(
            id: uniqueID(),
            name: uniqueName(base: source.map { "\($0.name) Copy" } ?? "New Preset"),
            input: source?.input ?? .max,
            points: source?.points ?? Self.starterPoints
        )
        do {
            try store.upsert(preset)
            try store.setActive(preset.id)
        } catch {
            fail("Save failed: \(error.localizedDescription)")
            return
        }
        lastError = nil
        deleteArmed = false
        draft = preset
        render()
        onLibraryChange?()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.nameField)
            self.nameField.selectText(nil)
        }
    }

    private func configure(width: CGFloat) {
        graph.onEdit = { [weak self] points in self?.graphEdited(points) }
        graph.onCommit = { [weak self] points in self?.graphCommitted(points) }
        graph.heightAnchor.constraint(equalToConstant: 200).isActive = true

        nameField.placeholderString = "Preset name"
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(nameCommitted(_:))
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setAccessibilityLabel("Preset name")

        for input in FanControlInput.allCases {
            inputPopup.addItem(withTitle: Self.title(for: input))
        }
        inputPopup.target = self
        inputPopup.action = #selector(inputChanged(_:))
        inputPopup.setContentHuggingPriority(.required, for: .horizontal)
        inputPopup.setAccessibilityLabel("Temperature input")

        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateTapped(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped(_:))
        for button in [duplicateButton, deleteButton] {
            button.controlSize = .small
            button.bezelStyle = .rounded
        }

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.preferredMaxLayoutWidth = width
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.preferredMaxLayoutWidth = width

        let nameRow = NSStackView(views: [nameField, inputPopup])
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        nameRow.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let buttonRow = NSStackView(views: [duplicateButton, deleteButton, spacer])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let rows: [NSView] = [graph, nameRow, buttonRow, hintLabel, errorLabel]
        editorStack.setViews(rows, in: .top)
        editorStack.orientation = .vertical
        editorStack.alignment = .leading
        editorStack.spacing = 8
        for row in rows {
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
        }

        editorStack.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorStack)
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            editorStack.topAnchor.constraint(equalTo: topAnchor),
            editorStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            editorStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func render() {
        guard let draft else {
            editorStack.isHidden = true
            placeholder.isHidden = false
            return
        }
        editorStack.isHidden = false
        placeholder.isHidden = true
        if nameField.currentEditor() == nil, nameField.stringValue != draft.name {
            nameField.stringValue = draft.name
        }
        if let index = FanControlInput.allCases.firstIndex(of: draft.input), inputPopup.indexOfSelectedItem != index {
            inputPopup.selectItem(at: index)
        }
        graph.setPoints(draft.points)
        deleteButton.isEnabled = store.library.presets.count > 1
        updateDeleteTitle()
        refreshLabels()
    }

    private func updateDeleteTitle() {
        let title = deleteArmed ? "Click again to delete" : "Delete"
        if deleteButton.title != title { deleteButton.title = title }
        deleteButton.contentTintColor = deleteArmed ? .systemRed : nil
    }

    private func refreshLabels() {
        var hint = "Drag a point to move it, double-click empty space to add one, right-click a point to remove it."
        if let input = draft?.input, input != .max {
            hint += " CPU or GPU at 95 \u{00B0}C or above still forces full speed."
        }
        if hintLabel.stringValue != hint { hintLabel.stringValue = hint }
        let message = lastError ?? ""
        if errorLabel.stringValue != message { errorLabel.stringValue = message }
    }

    private func commit() {
        guard var preset = draft else { return }
        preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preset.name.isEmpty else {
            let stored = store.library.preset(id: preset.id)?.name ?? ""
            draft?.name = stored
            nameField.stringValue = stored
            fail("Name cannot be empty")
            return
        }
        do {
            try preset.curve.validate()
        } catch {
            fail("Invalid curve: \(error)")
            return
        }
        guard preset != store.library.preset(id: preset.id) else {
            draft = preset
            return
        }
        do {
            try store.upsert(preset)
        } catch {
            fail("Save failed: \(error.localizedDescription)")
            return
        }
        draft = preset
        lastError = nil
        onLibraryChange?()
        refreshLabels()
    }

    private func fail(_ message: String) {
        lastError = message
        NSSound.beep()
        refreshLabels()
    }

    private func disarmDelete() {
        guard deleteArmed else { return }
        deleteArmed = false
        updateDeleteTitle()
    }

    private func graphEdited(_ points: [CurvePoint]) {
        guard draft != nil else { return }
        draft?.points = points
        lastError = nil
        disarmDelete()
        refreshLabels()
    }

    private func graphCommitted(_ points: [CurvePoint]) {
        guard draft != nil else { return }
        draft?.points = points
        commit()
    }

    @objc private func nameCommitted(_ sender: Any?) {
        guard draft != nil else { return }
        draft?.name = nameField.stringValue
        disarmDelete()
        commit()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        nameCommitted(nil)
    }

    @objc private func inputChanged(_ sender: Any?) {
        let index = inputPopup.indexOfSelectedItem
        guard draft != nil, FanControlInput.allCases.indices.contains(index) else { return }
        draft?.input = FanControlInput.allCases[index]
        disarmDelete()
        commit()
        render()
    }

    @objc private func duplicateTapped(_ sender: Any?) {
        addPreset(copying: draft)
    }

    @objc private func deleteTapped(_ sender: Any?) {
        guard let preset = draft, store.library.presets.count > 1 else { return }
        guard deleteArmed else {
            deleteArmed = true
            updateDeleteTitle()
            return
        }
        let before = store.library.presets
        let index = before.firstIndex { $0.id == preset.id } ?? 0
        do {
            try store.remove(id: preset.id)
            let remaining = store.library.presets
            if let next = remaining.indices.contains(index) ? remaining[index] : remaining.last {
                try store.setActive(next.id)
            }
        } catch {
            fail("Delete failed: \(error.localizedDescription)")
            return
        }
        deleteArmed = false
        lastError = nil
        draft = store.library.activePreset
        render()
        onLibraryChange?()
    }

    private func uniqueID() -> String {
        let existing = Set(store.library.presets.map(\.id))
        var number = existing.count + 1
        while existing.contains("custom-\(number)") || "custom-\(number)" == PresetLibrary.autoID {
            number += 1
        }
        return "custom-\(number)"
    }

    private func uniqueName(base: String) -> String {
        let existing = Set(store.library.presets.map(\.name))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }
}
