import AppKit

/// The layout editor window: pick a zone on the left, shape it on the right.
/// Every change writes through to disk immediately, so there is no Save button
/// to forget and no way to lose work by closing the window.
final class LayoutEditorWindowController: NSWindowController {

    var onChange: ((Config) -> Void)?

    private var config: Config
    private var selectedRow = 0

    private let table = NSTableView()
    private let nameField = NSTextField(string: "")
    private let columnsField = NSTextField(string: "2")
    private let rowsField = NSTextField(string: "2")
    private let columnsStepper = NSStepper()
    private let rowsStepper = NSStepper()
    private let grid = GridEditorView()
    private let sizeSlider = NSSlider()
    private let marginSlider = NSSlider()
    private let marginCaption = NSTextField(labelWithString: "Distance from edge")
    private let placementPopup = NSPopUpButton()
    private let removeButton = NSButton()

    init(config: Config) {
        self.config = config.sanitized

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Perch Layouts"
        window.center()
        super.init(window: window)

        buildInterface()
        table.reloadData()
        selectRow(0)
    }

    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        // Upper half: everything here belongs to the selected layout.
        content.addSubview(sectionLabel("Layouts", frame: NSRect(x: 20, y: 562, width: 220, height: 18)))

        // Zone list.
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 228, width: 232, height: 328))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("zone"))
        column.width = 210
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 46
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        scroll.documentView = table
        content.addSubview(scroll)

        let addButton = button("＋", action: #selector(addZone), width: 40)
        addButton.frame.origin = NSPoint(x: 20, y: 192)
        addButton.toolTip = "Add a layout"
        content.addSubview(addButton)

        removeButton.title = "－"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeZone)
        removeButton.frame = NSRect(x: 64, y: 192, width: 40, height: 28)
        removeButton.toolTip = "Remove the selected layout"
        content.addSubview(removeButton)

        let upButton = button("▲", action: #selector(moveZoneUp), width: 40)
        upButton.frame.origin = NSPoint(x: 116, y: 192)
        upButton.toolTip = "Move earlier in the strip"
        content.addSubview(upButton)

        let downButton = button("▼", action: #selector(moveZoneDown), width: 40)
        downButton.frame.origin = NSPoint(x: 160, y: 192)
        downButton.toolTip = "Move later in the strip"
        content.addSubview(downButton)

        // Name.
        content.addSubview(sectionLabel("Name", frame: NSRect(x: 276, y: 562, width: 200, height: 18)))
        nameField.frame = NSRect(x: 276, y: 534, width: 424, height: 24)
        nameField.delegate = self
        content.addSubview(nameField)

        // Divisions.
        content.addSubview(sectionLabel("Divisions", frame: NSRect(x: 276, y: 500, width: 200, height: 18)))
        configureCount(field: columnsField, stepper: columnsStepper, action: #selector(columnsChanged), x: 276, y: 472)
        content.addSubview(caption("columns", frame: NSRect(x: 276, y: 452, width: 80, height: 14)))
        configureCount(field: rowsField, stepper: rowsStepper, action: #selector(rowsChanged), x: 396, y: 472)
        content.addSubview(caption("rows", frame: NSRect(x: 396, y: 452, width: 80, height: 14)))
        for view in [columnsField, columnsStepper, rowsField, rowsStepper] {
            content.addSubview(view)
        }

        // Grid.
        content.addSubview(caption("Drag across the cells this layout should fill",
                                   frame: NSRect(x: 276, y: 420, width: 424, height: 14)))
        grid.frame = NSRect(x: 276, y: 252, width: 424, height: 160)
        grid.onSelectionChanged = { [weak self] selection in
            self?.updateSelectedZone { zone in
                zone.x = selection.x
                zone.y = selection.y
                zone.w = selection.w
                zone.h = selection.h
            }
        }
        content.addSubview(grid)

        // Lower band: settings for the strip as a whole. Kept full width and
        // below a rule so it reads as global — sitting it in the right-hand
        // column made it look like a property of the selected layout.
        let divider = NSBox(frame: NSRect(x: 20, y: 176, width: 680, height: 1))
        divider.boxType = .separator
        content.addSubview(divider)

        content.addSubview(sectionLabel("Icon Strip", frame: NSRect(x: 20, y: 142, width: 120, height: 18)))
        content.addSubview(caption("Applies to every layout",
                                   frame: NSRect(x: 104, y: 144, width: 200, height: 14)))

        content.addSubview(caption("Position", frame: NSRect(x: 20, y: 104, width: 80, height: 14)))
        placementPopup.frame = NSRect(x: 106, y: 98, width: 170, height: 25)
        placementPopup.addItems(withTitles: ["Middle of screen", "Top of screen", "Bottom of screen"])
        placementPopup.target = self
        placementPopup.action = #selector(placementChanged)
        content.addSubview(placementPopup)

        content.addSubview(caption("Icon size", frame: NSRect(x: 300, y: 104, width: 80, height: 14)))
        sizeSlider.frame = NSRect(x: 386, y: 98, width: 314, height: 24)
        sizeSlider.minValue = 56
        sizeSlider.maxValue = 124
        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(appearanceChanged)
        content.addSubview(sizeSlider)

        marginCaption.font = .systemFont(ofSize: 11)
        marginCaption.textColor = .secondaryLabelColor
        marginCaption.frame = NSRect(x: 20, y: 58, width: 80, height: 28)
        marginCaption.lineBreakMode = .byWordWrapping
        marginCaption.maximumNumberOfLines = 2
        content.addSubview(marginCaption)

        marginSlider.frame = NSRect(x: 106, y: 58, width: 170, height: 24)
        marginSlider.minValue = 0
        marginSlider.maxValue = 320
        marginSlider.isContinuous = true
        marginSlider.target = self
        marginSlider.action = #selector(appearanceChanged)
        content.addSubview(marginSlider)

        // Footer.
        let reset = button("Reset to Defaults", action: #selector(resetToDefaults), width: 160)
        reset.frame.origin = NSPoint(x: 20, y: 20)
        content.addSubview(reset)

        let reveal = button("Show Config File", action: #selector(revealConfig), width: 150)
        reveal.frame.origin = NSPoint(x: 188, y: 20)
        content.addSubview(reveal)

        let done = button("Done", action: #selector(closeWindow), width: 100)
        done.frame.origin = NSPoint(x: 600, y: 20)
        done.keyEquivalent = "\r"
        content.addSubview(done)

        sizeSlider.doubleValue = config.iconWidth
        marginSlider.doubleValue = config.topMargin
        syncPlacementControls()
    }

    /// The margin only means something when the strip is anchored to an edge,
    /// so it greys out rather than sitting there doing nothing when centred.
    private func syncPlacementControls() {
        switch config.resolvedPlacement {
        case .center:
            placementPopup.selectItem(at: 0)
            marginCaption.stringValue = "Distance from edge"
        case .top:
            placementPopup.selectItem(at: 1)
            marginCaption.stringValue = "Distance from top"
        case .bottom:
            placementPopup.selectItem(at: 2)
            marginCaption.stringValue = "Distance from bottom"
        }
        let anchored = config.resolvedPlacement != .center
        marginSlider.isEnabled = anchored
        marginCaption.textColor = anchored ? .secondaryLabelColor : .tertiaryLabelColor
    }

    private func sectionLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.frame = frame
        return label
    }

    private func caption(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = frame
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        return label
    }

    private func button(_ title: String, action: Selector, width: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        return button
    }

    private func configureCount(field: NSTextField, stepper: NSStepper, action: Selector, x: CGFloat, y: CGFloat) {
        field.frame = NSRect(x: x, y: y, width: 60, height: 22)
        field.alignment = .right
        field.isEditable = false
        field.isSelectable = false

        stepper.frame = NSRect(x: x + 64, y: y - 1, width: 19, height: 24)
        stepper.minValue = 1
        stepper.maxValue = 12
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    // MARK: - Selection

    private var selectedZone: Zone? {
        config.zones.indices.contains(selectedRow) ? config.zones[selectedRow] : nil
    }

    private func selectRow(_ row: Int) {
        guard !config.zones.isEmpty else { return }
        selectedRow = min(max(0, row), config.zones.count - 1)
        table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        syncDetailPane()
    }

    private func syncDetailPane() {
        guard let zone = selectedZone else { return }
        nameField.stringValue = zone.name
        columnsField.stringValue = String(zone.cols)
        rowsField.stringValue = String(zone.rows)
        columnsStepper.integerValue = zone.cols
        rowsStepper.integerValue = zone.rows
        grid.columns = zone.cols
        grid.rows = zone.rows
        grid.selection = GridSelection(x: zone.x, y: zone.y, w: zone.w, h: zone.h)
        removeButton.isEnabled = config.zones.count > 1
    }

    /// Mutates the selected zone, then persists. The single write path means
    /// disk, the drag overlay, and the list can never disagree.
    private func updateSelectedZone(_ mutate: (inout Zone) -> Void) {
        guard config.zones.indices.contains(selectedRow) else { return }
        mutate(&config.zones[selectedRow])
        commit(reloadRow: true)
    }

    private func commit(reloadRow: Bool = false, reloadAll: Bool = false) {
        config = config.sanitized
        ConfigStore.save(config)
        onChange?(config)
        if reloadAll {
            table.reloadData()
        } else if reloadRow {
            table.reloadData(forRowIndexes: IndexSet(integer: selectedRow),
                             columnIndexes: IndexSet(integer: 0))
        }
    }

    // MARK: - Actions

    @objc private func columnsChanged() {
        let value = max(1, columnsStepper.integerValue)
        columnsField.stringValue = String(value)
        grid.columns = value
        updateSelectedZone { zone in
            zone.cols = value
            zone.x = min(zone.x, value - 1)
            zone.w = min(zone.w, value - zone.x)
        }
        syncDetailPane()
    }

    @objc private func rowsChanged() {
        let value = max(1, rowsStepper.integerValue)
        rowsField.stringValue = String(value)
        grid.rows = value
        updateSelectedZone { zone in
            zone.rows = value
            zone.y = min(zone.y, value - 1)
            zone.h = min(zone.h, value - zone.y)
        }
        syncDetailPane()
    }

    @objc private func placementChanged() {
        switch placementPopup.indexOfSelectedItem {
        case 1: config.placement = .top
        case 2: config.placement = .bottom
        default: config.placement = .center
        }
        syncPlacementControls()
        commit()
    }

    @objc private func appearanceChanged() {
        config.iconWidth = sizeSlider.doubleValue.rounded()
        config.iconHeight = (sizeSlider.doubleValue * 0.68).rounded()
        config.topMargin = marginSlider.doubleValue.rounded()
        commit()
    }

    @objc private func addZone() {
        let new = Zone(name: "New Layout", cols: 2, rows: 2, x: 0, y: 0, w: 1, h: 1)
        config.zones.insert(new, at: min(selectedRow + 1, config.zones.count))
        commit(reloadAll: true)
        selectRow(selectedRow + 1)
    }

    @objc private func removeZone() {
        guard config.zones.count > 1, config.zones.indices.contains(selectedRow) else {
            NSSound.beep()
            return
        }
        config.zones.remove(at: selectedRow)
        commit(reloadAll: true)
        selectRow(selectedRow)
    }

    @objc private func moveZoneUp() {
        guard selectedRow > 0 else { return }
        config.zones.swapAt(selectedRow, selectedRow - 1)
        commit(reloadAll: true)
        selectRow(selectedRow - 1)
    }

    @objc private func moveZoneDown() {
        guard selectedRow < config.zones.count - 1 else { return }
        config.zones.swapAt(selectedRow, selectedRow + 1)
        commit(reloadAll: true)
        selectRow(selectedRow + 1)
    }

    @objc private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset to the default layouts?"
        alert.informativeText = "Your current layouts will be replaced. This cannot be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        config = .fallback
        sizeSlider.doubleValue = config.iconWidth
        marginSlider.doubleValue = config.topMargin
        syncPlacementControls()
        commit(reloadAll: true)
        selectRow(0)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.url])
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }
}

// MARK: - Table

extension LayoutEditorWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        config.zones.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard config.zones.indices.contains(row) else { return nil }
        let zone = config.zones[row]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 46))

        let icon = ZoneIconView(frame: NSRect(x: 4, y: 5, width: 54, height: 36))
        icon.zone = zone
        container.addSubview(icon)

        let label = NSTextField(labelWithString: zone.name)
        label.frame = NSRect(x: 68, y: 13, width: 136, height: 20)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)

        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return }
        selectedRow = table.selectedRow
        syncDetailPane()
    }
}

// MARK: - Name editing

extension LayoutEditorWindowController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === nameField else { return }
        let text = nameField.stringValue
        updateSelectedZone { $0.name = text }
    }
}
