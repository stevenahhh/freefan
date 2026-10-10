import AppKit
import SwiftUI
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
    private let settings: SettingsStore
    private let actions: PopoverActions
    private let headerModel = HeaderModel()
    private lazy var header = NSHostingView(rootView: HeaderContent(model: headerModel))
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private let slider = PresetSliderView(width: Layout.inner)
    private let editor: CurveEditorPanel
    private let settingsPanel: SettingsPanel
    let footer = PopoverFooter(width: Layout.inner)
    let helpBubble = HelpBubbleView()
    private var snapshot: LiveSnapshot?
    private(set) var showingSettings = false

    init(store: PresetStore, settings: SettingsStore, actions: PopoverActions) {
        self.store = store
        self.settings = settings
        self.actions = actions
        self.editor = CurveEditorPanel(store: store, width: Layout.inner)
        self.settingsPanel = SettingsPanel(settings: settings, width: Layout.inner)
        super.init(nibName: nil, bundle: nil)
        headerModel.showsRPM = settings.settings.fanUnitsRPM
        headerModel.onUnitsChanged = { [weak self] showsRPM in
            guard let self else { return }
            self.settings.setFanUnitsRPM(showsRPM)
            self.saveSettings()
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        slider.onSelect = { [weak self] id in self?.select(id) }
        slider.onNew = { [weak self] in
            guard let self else { return }
            self.editor.addPreset(copying: self.store.library.activePreset)
        }
        editor.onLibraryChange = { [weak self] in self?.libraryChanged() }
        settingsPanel.onChange = { [weak self] in self?.actions.settingsChanged() }
        settingsPanel.isHidden = true
        footer.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        footer.onHelpChange = { [weak self] shown in
            if shown {
                self?.showHelpBubble()
            } else {
                self?.helpBubble.isHidden = true
            }
        }
        helpBubble.isHidden = true

        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        warningLabel.preferredMaxLayoutWidth = Layout.inner
        warningLabel.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator

        let sections: [NSView] = [header, warningLabel, slider, editor, settingsPanel, separator, footer]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(8, after: header)
        stack.setCustomSpacing(8, after: warningLabel)
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

        slider.reload(library: store.library)
        editor.showActive()
        resize()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nil)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        footer.dismissHelp()
    }

    func update(_ snapshot: LiveSnapshot) {
        guard isViewLoaded else { return }
        self.snapshot = snapshot

        let warning = warning(for: snapshot)
        let text = warning ?? ""
        if warningLabel.stringValue != text { warningLabel.stringValue = text }
        warningLabel.isHidden = warning == nil

        let readout = HeaderReadout(reading: snapshot.reading, fans: snapshot.fans)
        if headerModel.readout != readout { headerModel.readout = readout }
        footer.update(pressure: snapshot.pressure)

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

    private func saveSettings() {
        do {
            try settings.save()
            actions.settingsChanged()
        } catch {
            editor.report("Not saved: \(error.localizedDescription)")
        }
    }

    private func select(_ id: String) {
        do {
            try store.setActive(id)
        } catch {
            editor.report("Save failed: \(error.localizedDescription)")
        }
        editor.showActive()
        slider.reload(library: store.library)
        actions.presetsChanged()
        refreshHeader()
        resize()
    }

    private func libraryChanged() {
        slider.reload(library: store.library)
        resize()
        actions.presetsChanged()
        refreshHeader()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let page = menu.addItem(
            withTitle: showingSettings ? "Back to Presets" : "Menu Bar Text\u{2026}",
            action: #selector(pageTapped(_:)),
            keyEquivalent: ""
        )
        page.target = self
        let helper = menu.addItem(
            withTitle: snapshot?.helperInstalled == true ? "Uninstall Helper\u{2026}" : "Install Helper\u{2026}",
            action: #selector(helperTapped(_:)),
            keyEquivalent: ""
        )
        helper.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit FreeFan", action: #selector(quitTapped(_:)), keyEquivalent: "q")
        quit.target = self
        return menu
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
        footer.dismissHelp()
        slider.isHidden = showingSettings
        editor.isHidden = showingSettings
        settingsPanel.isHidden = !showingSettings
        resize()
    }

    @objc private func quitTapped(_ sender: Any?) {
        actions.quit()
    }

    private func warning(for snapshot: LiveSnapshot) -> String? {
        if !snapshot.helperInstalled {
            return "Helper not installed. Fans stay on Auto until you install it from the menu."
        }
        if !snapshot.helperConnected {
            return "Helper not responding. Reconnecting\u{2026}"
        }
        if let error = snapshot.helperError, !error.isEmpty {
            return "Helper: \(error)"
        }
        switch snapshot.helperStatus?.mode {
        case .panic?:
            return "Panic: a temperature reached 95 \u{00B0}C, fans at full speed."
        case .monitor?:
            return "Helper stopped controlling the fans (\(snapshot.helperStatus?.error ?? "write failed"))."
        default:
            return nil
        }
    }

    private static func maxRPM(of snapshot: LiveSnapshot) -> Float? {
        let spinning = snapshot.reading?.fans.filter { $0.rpm != nil }.max { ($0.rpm ?? 0) < ($1.rpm ?? 0) }
        guard let fan = spinning else { return nil }
        return snapshot.fans.first { $0.index == fan.index }?.maxRPM
    }
}
