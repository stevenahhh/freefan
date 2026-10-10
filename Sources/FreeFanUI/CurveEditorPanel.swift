import AppKit
import FreeFanCore
import FreeFanSMC

final class CurveEditorPanel: NSView {
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

    private let store: PresetStore
    private let graph = CurveEditorView(frame: .zero)
    private let nameEditor = PresetNameEditor()
    private let inputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(wrappingLabelWithString: """
        Auto: macOS controls the fans.
        Choose a preset above to apply it, or duplicate one to make it yours.
        """)
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
        nameEditor.endEditing()
        draft = store.library.activePreset
        render()
    }

    func updateLive(temperature: Float?, rpm: Float?, fanMaxRPM: Float?) {
        graph.setLive(temperature: temperature, actualRPM: rpm, fanMaxRPM: fanMaxRPM)
    }

    func report(_ message: String) {
        lastError = message
        refreshError()
    }

    func addPreset(copying source: Preset?) {
        let preset = store.library.newCustomPreset(copying: source)
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
        nameEditor.beginEditing()
        onLibraryChange?()
    }

    private func configure(width: CGFloat) {
        graph.onEdit = { [weak self] points in self?.graphEdited(points) }
        graph.onCommit = { [weak self] points in self?.graphCommitted(points) }
        graph.heightAnchor.constraint(equalToConstant: 200).isActive = true

        nameEditor.onCommit = { [weak self] name in self?.commitName(name) }
        nameEditor.onError = { [weak self] message in self?.fail(message) }

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

        noteLabel.font = .systemFont(ofSize: 10)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = width
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.preferredMaxLayoutWidth = width

        nameEditor.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let nameRow = NSStackView(views: [nameEditor, inputPopup])
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        nameRow.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let buttonRow = NSStackView(views: [duplicateButton, deleteButton, spacer])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let rows: [NSView] = [graph, nameRow, buttonRow, noteLabel, errorLabel]
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

        let builtIn = draft.isBuiltIn
        graph.isEditable = !builtIn
        graph.setPoints(draft.points)
        nameEditor.set(name: draft.name, isBuiltIn: builtIn)
        inputPopup.isEnabled = !builtIn
        inputPopup.toolTip = builtIn ? "Built-in presets keep this setting" : "Temperature the curve follows"
        if let index = FanControlInput.allCases.firstIndex(of: draft.input), inputPopup.indexOfSelectedItem != index {
            inputPopup.selectItem(at: index)
        }
        duplicateButton.title = builtIn ? "Duplicate to Edit" : "Duplicate"
        deleteButton.isHidden = builtIn
        updateDeleteTitle()

        let note = draft.editorNote
        if noteLabel.stringValue != note { noteLabel.stringValue = note }
        noteLabel.isHidden = note.isEmpty
        refreshError()
    }

    private func updateDeleteTitle() {
        let title = deleteArmed ? "Click again to delete" : "Delete"
        if deleteButton.title != title { deleteButton.title = title }
        deleteButton.contentTintColor = deleteArmed ? .systemRed : nil
    }

    private func refreshError() {
        let message = lastError ?? ""
        if errorLabel.stringValue != message { errorLabel.stringValue = message }
    }

    private func apply(_ preset: Preset) {
        do {
            try preset.curve.validate()
        } catch {
            fail("Invalid curve: \(error)")
            return
        }
        guard preset != store.library.preset(id: preset.id) else {
            draft = preset
            render()
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
        render()
        onLibraryChange?()
    }

    private func fail(_ message: String) {
        lastError = message
        NSSound.beep()
        refreshError()
        nameEditor.keepEditing()
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
        refreshError()
    }

    private func graphCommitted(_ points: [CurvePoint]) {
        guard var draft else { return }
        draft.points = points
        apply(draft)
    }

    private func commitName(_ name: String) {
        guard var draft else { return }
        draft.name = name
        apply(draft)
    }

    @objc private func inputChanged(_ sender: Any?) {
        let index = inputPopup.indexOfSelectedItem
        guard var draft, FanControlInput.allCases.indices.contains(index) else { return }
        draft.input = FanControlInput.allCases[index]
        disarmDelete()
        apply(draft)
    }

    @objc private func duplicateTapped(_ sender: Any?) {
        addPreset(copying: draft)
    }

    @objc private func deleteTapped(_ sender: Any?) {
        guard let preset = draft, !preset.isBuiltIn else { return }
        guard deleteArmed else {
            deleteArmed = true
            updateDeleteTitle()
            return
        }
        do {
            try store.remove(id: preset.id)
        } catch {
            fail("Delete failed: \(error.localizedDescription)")
            return
        }
        deleteArmed = false
        lastError = nil
        nameEditor.endEditing()
        draft = store.library.activePreset
        render()
        onLibraryChange?()
    }
}
