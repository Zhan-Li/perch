import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let overlay = OverlayController()
    private let monitor = DragMonitor()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var editor: LayoutEditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.reload(ConfigStore.load())
        buildStatusItem()
        wireMonitor()
        startWhenPermitted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Permission

    /// The event tap cannot be created until the user has ticked us in
    /// System Settings, and macOS gives no notification when they do — so we
    /// prompt once and then poll quietly until it lands.
    private func startWhenPermitted() {
        if AX.isTrusted(prompt: false) {
            begin()
            return
        }

        _ = AX.isTrusted(prompt: true)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AX.isTrusted(prompt: false) else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.begin()
        }
    }

    private func begin() {
        guard monitor.start() else {
            presentTapFailure()
            return
        }
    }

    private func presentTapFailure() {
        let alert = NSAlert()
        alert.messageText = "Perch couldn’t watch for window drags"
        alert.informativeText = """
            macOS refused the event tap. This usually means Accessibility access \
            was granted to an older copy of Perch. Remove Perch from \
            System Settings ▸ Privacy & Security ▸ Accessibility, then add it again.
            """
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Drag handling

    private func wireMonitor() {
        monitor.onBegan = { [weak self] point in
            self?.overlay.follow(cursor: point)
        }

        monitor.onMoved = { [weak self] point in
            self?.overlay.follow(cursor: point)
        }

        monitor.onEnded = { [weak self] window, point in
            guard let self else { return }
            let index = self.overlay.updateHover(at: point)
            let target = index.flatMap { self.overlay.targetFrame(for: $0) }
            self.overlay.hide()
            guard let target else { return }

            // The app is still settling its own drag on mouse-up, so write the
            // frame once now and once on the next turn of the run loop.
            let first = AX.setFrame(window, target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                let second = AX.setFrame(window, target)
                if Log.isEnabled {
                    let owner = AX.pid(window).flatMap {
                        NSRunningApplication(processIdentifier: $0)?.localizedName
                    } ?? "unknown"
                    Log.write("""
                        drop app=\(owner) target=\(target)
                          pass1 before=\(String(describing: first.before)) \
                        after=\(String(describing: first.after)) \
                        posSettable=\(first.positionSettable) sizeSettable=\(first.sizeSettable) \
                        enhancedUI=\(first.hadEnhancedUI) errors=\(first.errors) resized=\(first.resized)
                          pass2 after=\(String(describing: second.after)) \
                        errors=\(second.errors) resized=\(second.resized)
                        """)
                }
            }
        }

        monitor.onCancelled = { [weak self] in
            self?.overlay.hide()
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.split.2x2",
            accessibilityDescription: "Perch"
        )
        item.button?.image?.isTemplate = true

        // Rebuilt on every open rather than cached, so the permission line can
        // never claim we are still waiting once access has actually landed.
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AX.isTrusted(prompt: false)

        if !trusted {
            let warning = NSMenuItem(
                title: "Waiting for Accessibility access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let edit = NSMenuItem(title: "Edit Layouts…", action: #selector(editLayouts), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func editLayouts() {
        if editor == nil {
            let controller = LayoutEditorWindowController(config: ConfigStore.load())
            controller.onChange = { [weak self] config in
                self?.overlay.reload(config)
            }
            editor = controller
        }
        // A menu-bar-only app has no Dock icon to click, so it has to raise
        // itself before the window can take focus.
        NSApp.activate(ignoringOtherApps: true)
        editor?.showWindow(nil)
        editor?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
