import AppKit
import FreeFanCore
import FreeFanSMC

/// NSWindow that routes the standard editing shortcuts to the first responder. An accessory (menu bar) app
/// has no Edit menu, so without this the name field would not accept cmd-C / cmd-V / cmd-X / cmd-A.
private final class EditorWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers else { return false }
        switch key {
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "w":
            performClose(nil)
            return true
        default: return false
        }
    }
}

/// Owns the curve editor window. The window and every view in it are created on show() and released after
/// the window closes, so an idle app holds none of them.
final class CurveEditorWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let margin: CGFloat = 16
        static let rowGap: CGFloat = 12
        static let controlGap: CGFloat = 8
        static let initialSize = NSSize(width: 700, height: 560)
        static let minimumSize = NSSize(width: 580, height: 460)
        static let popupMinWidth: CGFloat = 200
        static let popupMaxWidth: CGFloat = 340
        static let inputPopupWidth: CGFloat = 150
        static let graphMinHeight: CGFloat = 260
    }

    private static let frameAutosaveName = "FreeFanCurveEditor"
    private static let starterPoints = [
        CurvePoint(t: 40, p: 10),
        CurvePoint(t: 60, p: 30),
        CurvePoint(t: 80, p: 60),
        CurvePoint(t: 95, p: 100),
    ]

    private struct ShownState: Equatable {
        var hasDraft: Bool
        var dirty: Bool
        var canDelete: Bool
        var status: String
        var isError: Bool
    }

    private let store: PresetStore
    private let onChange: () -> Void

    private var editorWindow: NSWindow?
    private var graphView: CurveEditorView?
    private var presetPopup: NSPopUpButton?
    private var nameField: NSTextField?
    private var inputPopup: NSPopUpButton?
    private var newButton: NSButton?
    private var duplicateButton: NSButton?
    private var deleteButton: NSButton?
    private var revertButton: NSButton?
    private var saveButton: NSButton?
    private var statusLabel: NSTextField?

    private var open = false
    private var draft: Preset?
    private var lastError: String?
    private var shownState: ShownState?

    private var liveTemperature: Float?
    private var liveRPM: Float?
    private var liveFanMaxRPM: Float?

    init(store: PresetStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        super.init(window: nil)
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var isOpen: Bool { open }

    func show() {
        if editorWindow != nil, !open {
            tearDown()
        }
        if let window = editorWindow {
            reloadPresetList(selecting: draft?.id, keepDraft: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = buildWindow()
            editorWindow = window
            self.window = window
            let library = store.library
            reloadPresetList(selecting: library.preset(id: library.active) != nil ? library.active : nil, keepDraft: false)
            graphView?.setLive(temperature: liveTemperature, actualRPM: liveRPM, fanMaxRPM: liveFanMaxRPM)
            window.makeKeyAndOrderFront(nil)
        }
        open = true
        NSApp.activate()
    }

    func updateLive(temperature: Float?, actualRPM: Float?, fanMaxRPM: Float?) {
        liveTemperature = temperature
        liveRPM = actualRPM
        liveFanMaxRPM = fanMaxRPM
        graphView?.setLive(temperature: temperature, actualRPM: actualRPM, fanMaxRPM: fanMaxRPM)
    }

    func windowWillClose(_ notification: Notification) {
        open = false
        graphView?.onEdit = nil
        // Release after the close finishes so AppKit is not left holding a deallocated window mid-close.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.open else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        editorWindow?.delegate = nil
        editorWindow?.contentView = nil
        self.window = nil
        editorWindow = nil
        graphView?.onEdit = nil
        graphView = nil
        presetPopup = nil
        nameField = nil
        inputPopup = nil
        newButton = nil
        duplicateButton = nil
        deleteButton = nil
        revertButton = nil
        saveButton = nil
        statusLabel = nil
        draft = nil
        lastError = nil
        shownState = nil
    }

    private func buildWindow() -> NSWindow {
        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: Layout.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FreeFan Curves"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Layout.minimumSize
        window.delegate = self
        window.contentView = buildContent()
        window.center()
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }

    private func buildContent() -> NSView {
        let container = NSView()

        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        presetPopup.setAccessibilityLabel("Preset")
        presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.popupMinWidth).isActive = true
        presetPopup.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.popupMaxWidth).isActive = true

        let newButton = NSButton(title: "New", target: self, action: #selector(newPreset(_:)))
        let duplicateButton = NSButton(title: "Duplicate", target: self, action: #selector(duplicatePreset(_:)))
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deletePreset(_:)))
        deleteButton.hasDestructiveAction = true

        let presetRow = NSStackView(views: [presetPopup, newButton, duplicateButton, deleteButton, makeSpacer()])
        configure(row: presetRow)

        let nameLabel = NSTextField(labelWithString: "Name")
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Preset name"
        nameField.isContinuous = true
        nameField.target = self
        nameField.action = #selector(nameEdited(_:))
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setAccessibilityLabel("Preset name")

        let inputLabel = NSTextField(labelWithString: "Input")
        let inputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for input in FanControlInput.allCases {
            inputPopup.addItem(withTitle: Self.title(for: input))
        }
        inputPopup.target = self
        inputPopup.action = #selector(inputChanged(_:))
        inputPopup.setAccessibilityLabel("Temperature input")
        inputPopup.widthAnchor.constraint(equalToConstant: Layout.inputPopupWidth).isActive = true

        let detailRow = NSStackView(views: [nameLabel, nameField, inputLabel, inputPopup])
        configure(row: detailRow)

        let graph = CurveEditorView(frame: .zero)
        graph.onEdit = { [weak self] points in
            self?.graphEdited(points)
        }
        graph.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.graphMinHeight).isActive = true

        let hint = NSTextField(labelWithString: "Drag a dot to move it. Double-click empty space to add a point. Right-click a dot to remove it.")
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let revertButton = NSButton(title: "Revert", target: self, action: #selector(revertPreset(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreset(_:)))
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command

        let footerRow = NSStackView(views: [statusLabel, revertButton, saveButton])
        configure(row: footerRow)

        let views: [NSView] = [presetRow, detailRow, graph, hint, footerRow]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            ])
        }
        NSLayoutConstraint.activate([
            presetRow.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.margin),
            detailRow.topAnchor.constraint(equalTo: presetRow.bottomAnchor, constant: Layout.controlGap),
            graph.topAnchor.constraint(equalTo: detailRow.bottomAnchor, constant: Layout.rowGap),
            hint.topAnchor.constraint(equalTo: graph.bottomAnchor, constant: Layout.controlGap),
            footerRow.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: Layout.rowGap),
            footerRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.margin),
        ])

        self.graphView = graph
        self.presetPopup = presetPopup
        self.nameField = nameField
        self.inputPopup = inputPopup
        self.newButton = newButton
        self.duplicateButton = duplicateButton
        self.deleteButton = deleteButton
        self.revertButton = revertButton
        self.saveButton = saveButton
        self.statusLabel = statusLabel
        return container
    }

    private func configure(row: NSStackView) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Layout.controlGap
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        return spacer
    }

    private static func title(for input: FanControlInput) -> String {
        switch input {
        case .max: return "Max (CPU or GPU)"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }

    private func reloadPresetList(selecting id: String?, keepDraft: Bool) {
        guard let popup = presetPopup else { return }
        let library = store.library
        popup.removeAllItems()
        for preset in library.presets {
            let title = preset.id == library.active ? "\(preset.name)  (active)" : preset.name
            let item = NSMenuItem(title: title, action: #selector(presetSelectionChanged(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            popup.menu?.addItem(item)
        }
        popup.isEnabled = !library.presets.isEmpty

        let targetID = id.flatMap { library.preset(id: $0)?.id } ?? library.presets.first?.id
        if let targetID, let index = library.presets.firstIndex(where: { $0.id == targetID }) {
            popup.selectItem(at: index)
        }
        if keepDraft, draft != nil, draft?.id == targetID {
            refreshState()
        } else {
            loadDraft(id: targetID)
        }
    }

    private func loadDraft(id: String?) {
        draft = id.flatMap { store.library.preset(id: $0) }
        nameField?.stringValue = draft?.name ?? ""
        if let input = draft?.input, let index = FanControlInput.allCases.firstIndex(of: input) {
            inputPopup?.selectItem(at: index)
        }
        graphView?.setPoints(draft?.points ?? [])
        refreshState()
    }

    private var isDirty: Bool {
        guard let draft else { return false }
        return draft != store.library.preset(id: draft.id)
    }

    /// Pushes enabled states and the status text to the controls, touching them only when something changed
    /// so a drag does not churn AppKit.
    private func refreshState() {
        let dirty = isDirty
        let status: String
        if let lastError {
            status = lastError
        } else {
            status = dirty ? "Unsaved changes" : ""
        }
        let state = ShownState(
            hasDraft: draft != nil,
            dirty: dirty,
            canDelete: draft != nil && store.library.presets.count > 1,
            status: status,
            isError: lastError != nil
        )
        guard state != shownState else { return }
        shownState = state

        nameField?.isEnabled = state.hasDraft
        inputPopup?.isEnabled = state.hasDraft
        duplicateButton?.isEnabled = state.hasDraft
        deleteButton?.isEnabled = state.canDelete
        saveButton?.isEnabled = state.hasDraft && state.dirty
        revertButton?.isEnabled = state.hasDraft && state.dirty
        statusLabel?.stringValue = state.status
        statusLabel?.textColor = state.isError ? .systemRed : .secondaryLabelColor
    }

    private func fail(_ message: String) {
        lastError = message
        NSSound.beep()
        refreshState()
    }

    private func graphEdited(_ points: [CurvePoint]) {
        guard draft != nil else { return }
        draft?.points = points
        lastError = nil
        refreshState()
    }

    @objc private func presetSelectionChanged(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String, id != draft?.id else { return }
        lastError = nil
        loadDraft(id: id)
    }

    @objc private func nameEdited(_ sender: Any?) {
        guard draft != nil, let name = nameField?.stringValue else { return }
        draft?.name = name
        lastError = nil
        refreshState()
    }

    @objc private func inputChanged(_ sender: Any?) {
        guard draft != nil, let index = inputPopup?.indexOfSelectedItem,
              FanControlInput.allCases.indices.contains(index) else { return }
        draft?.input = FanControlInput.allCases[index]
        lastError = nil
        refreshState()
    }

    @objc private func newPreset(_ sender: Any?) {
        add(Preset(
            id: uniqueID(),
            name: uniqueName(base: "New Preset"),
            input: .max,
            points: Self.starterPoints
        ))
    }

    @objc private func duplicatePreset(_ sender: Any?) {
        guard let source = draft else { return }
        add(Preset(
            id: uniqueID(),
            name: uniqueName(base: "\(source.name) Copy"),
            input: source.input,
            points: source.points
        ))
    }

    private func add(_ preset: Preset) {
        lastError = nil
        var failure: String?
        do {
            try store.upsert(preset)
        } catch {
            failure = "Save failed: \(error.localizedDescription)"
        }
        reloadPresetList(selecting: preset.id, keepDraft: false)
        if let failure { fail(failure) }
        onChange()
    }

    @objc private func deletePreset(_ sender: Any?) {
        guard let preset = draft, let window = editorWindow else { return }
        guard store.library.presets.count > 1 else {
            fail("Keep at least one preset")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(preset.name)\"?"
        alert.informativeText = "This preset is removed from disk and cannot be restored."
        alert.alertStyle = .warning
        let deleteAction = alert.addButton(withTitle: "Delete")
        deleteAction.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete(id: preset.id)
        }
    }

    private func performDelete(id: String) {
        let before = store.library.presets
        guard before.count > 1, let index = before.firstIndex(where: { $0.id == id }) else { return }
        lastError = nil
        var failure: String?
        do {
            try store.remove(id: id)
        } catch {
            failure = "Delete failed: \(error.localizedDescription)"
        }
        let remaining = store.library.presets
        reloadPresetList(selecting: remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id, keepDraft: false)
        if let failure { fail(failure) }
        onChange()
    }

    @objc private func savePreset(_ sender: Any?) {
        guard var preset = draft else { return }
        preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preset.name.isEmpty else {
            fail("Name cannot be empty")
            return
        }
        do {
            try preset.curve.validate()
        } catch {
            fail("Invalid curve: \(error)")
            return
        }
        do {
            try store.upsert(preset)
        } catch {
            fail("Save failed: \(error.localizedDescription)")
            return
        }
        lastError = nil
        reloadPresetList(selecting: preset.id, keepDraft: false)
        onChange()
    }

    @objc private func revertPreset(_ sender: Any?) {
        guard let id = draft?.id else { return }
        lastError = nil
        loadDraft(id: id)
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
