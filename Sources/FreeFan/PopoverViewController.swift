import AppKit
import FreeFanCore
import FreeFanSMC

struct LiveSnapshot {
    var reading: SensorReading?
    var fans: [FanInfo]
    var pressure: MemoryPressure?
    var helperInstalled: Bool
    var helperConnected: Bool
    var helperStatus: HelperStatus?
    var helperError: String?
}

struct PopoverActions {
    var presetsChanged: () -> Void
    var settingsChanged: () -> Void
    var installHelper: () -> Void
    var uninstallHelper: () -> Void
    var quit: () -> Void
}

final class PopoverViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 380
        static let margin: CGFloat = 16
        static let inner: CGFloat = width - margin * 2
    }

    /// Called with the content size the popover should take. A shown NSPopover follows `contentSize`, not
    /// `preferredContentSize`, so whoever owns the popover applies it.
    var onPreferredSizeChange: ((NSSize) -> Void)?

    private let store: PresetStore
    private let actions: PopoverActions
    private let header = TelemetryHeaderView(width: Layout.inner)
    private let chips = PresetChipsView(width: Layout.inner)
    private let editor: CurveEditorPanel
    private let settingsPanel: SettingsPanel
    private let helperButton = NSButton(title: "", target: nil, action: nil)
    private let pageButton = NSButton(title: "", target: nil, action: nil)
    private var snapshot: LiveSnapshot?
    private var showingSettings = false

    init(store: PresetStore, settings: SettingsStore, actions: PopoverActions) {
        self.store = store
        self.actions = actions
        self.editor = CurveEditorPanel(store: store, width: Layout.inner)
        self.settingsPanel = SettingsPanel(settings: settings, width: Layout.inner)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        chips.onSelect = { [weak self] id in self?.select(id) }
        chips.onNew = { [weak self] in
            guard let self else { return }
            self.editor.addPreset(copying: self.store.library.activePreset)
        }
        editor.onLibraryChange = { [weak self] in self?.libraryChanged() }
        settingsPanel.onChange = { [weak self] in self?.actions.settingsChanged() }
        settingsPanel.isHidden = true

        helperButton.target = self
        helperButton.action = #selector(helperTapped(_:))
        pageButton.target = self
        pageButton.action = #selector(pageTapped(_:))
        updatePageButton()
        let quitButton = NSButton(title: "Quit FreeFan", target: self, action: #selector(quitTapped(_:)))
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = .command
        for button in [helperButton, pageButton, quitButton] {
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .secondaryLabelColor
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let footer = NSStackView(views: [helperButton, pageButton, spacer, quitButton])
        footer.orientation = .horizontal
        footer.spacing = 14

        let separator = NSBox()
        separator.boxType = .separator

        let sections: [NSView] = [header, chips, editor, settingsPanel, separator, footer]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: Layout.margin, left: Layout.margin, bottom: 12, right: Layout.margin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for section in sections {
            section.widthAnchor.constraint(equalToConstant: Layout.inner).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: Layout.width).isActive = true

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        chips.reload(library: store.library)
        editor.showActive()
        resize()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nil)
    }

    func update(_ snapshot: LiveSnapshot) {
        guard isViewLoaded else { return }
        self.snapshot = snapshot
        let description = modeDescription(for: snapshot)
        header.update(snapshot, mode: description.text, isWarning: description.warning)

        let title = snapshot.helperInstalled ? "Uninstall Helper\u{2026}" : "Install Helper\u{2026}"
        if helperButton.title != title { helperButton.title = title }

        settingsPanel.update(values: MenuBarValues(reading: snapshot.reading, presetName: store.library.activePreset?.name ?? "Auto"))

        let temperature = editor.activeInput.flatMap { snapshot.reading?.input($0) }
        editor.updateLive(
            temperature: temperature,
            rpm: snapshot.reading?.fans.compactMap { $0.rpm }.max(),
            fanMaxRPM: Self.maxRPM(of: snapshot)
        )
    }

    private func resize() {
        guard let stack = view.subviews.first as? NSStackView else { return }
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        guard abs(size.height - preferredContentSize.height) > 1 else { return }
        view.frame.size = size
        preferredContentSize = size
        onPreferredSizeChange?(size)
    }

    private func refreshHeader() {
        if let snapshot { update(snapshot) }
    }

    private func select(_ id: String) {
        do {
            try store.setActive(id)
        } catch {
            editor.report("Save failed: \(error.localizedDescription)")
        }
        editor.showActive()
        chips.reload(library: store.library)
        actions.presetsChanged()
        refreshHeader()
    }

    private func libraryChanged() {
        chips.reload(library: store.library)
        resize()
        actions.presetsChanged()
        refreshHeader()
    }

    @objc private func helperTapped(_ sender: Any?) {
        if snapshot?.helperInstalled == true {
            actions.uninstallHelper()
        } else {
            actions.installHelper()
        }
    }

    @objc private func pageTapped(_ sender: Any?) {
        showingSettings.toggle()
        view.window?.makeFirstResponder(nil)
        chips.isHidden = showingSettings
        editor.isHidden = showingSettings
        settingsPanel.isHidden = !showingSettings
        updatePageButton()
        resize()
    }

    private func updatePageButton() {
        let title = showingSettings ? "Back to Presets" : "Menu Bar Text\u{2026}"
        let symbol = showingSettings ? "chevron.backward" : "textformat"
        if pageButton.title != title { pageButton.title = title }
        pageButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        pageButton.imagePosition = .imageLeading
    }

    @objc private func quitTapped(_ sender: Any?) {
        actions.quit()
    }

    private func modeDescription(for snapshot: LiveSnapshot) -> (text: String, warning: Bool) {
        if !snapshot.helperInstalled {
            return ("Helper not installed. Fans stay on Auto until you install it below.", true)
        }
        if !snapshot.helperConnected {
            return ("Helper not responding. Reconnecting\u{2026}", true)
        }
        if let error = snapshot.helperError, !error.isEmpty {
            return ("Helper: \(error)", true)
        }
        let library = store.library
        switch snapshot.helperStatus?.mode {
        case .curve?, .fixed?:
            let name = library.activePreset?.name ?? "Custom"
            let input = library.activePreset.map { CurveEditorPanel.title(for: $0.input) } ?? ""
            return ("\(name): fan curve on \(input)", false)
        case .panic?:
            return ("Panic: CPU or GPU at 95 \u{00B0}C or above, fans at full speed.", true)
        case .monitor?:
            return ("Helper stopped controlling the fans (\(snapshot.helperStatus?.error ?? "write failed")).", true)
        case .auto?, nil:
            if library.active == PresetLibrary.autoID { return ("Auto: macOS controls the fans.", false) }
            return ("Applying \(library.activePreset?.name ?? "preset")\u{2026}", false)
        }
    }

    private static func maxRPM(of snapshot: LiveSnapshot) -> Float? {
        let spinning = snapshot.reading?.fans.filter { $0.rpm != nil }.max { ($0.rpm ?? 0) < ($1.rpm ?? 0) }
        guard let fan = spinning else { return nil }
        return snapshot.fans.first { $0.index == fan.index }?.maxRPM
    }
}
