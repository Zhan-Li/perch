import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let overlay = OverlayController()
    private let monitor = DragMonitor()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var editor: LayoutEditorWindowController?
    private var permissionAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.reload(ConfigStore.load())
        buildStatusItem()
        wireMonitor()
        Log.write("launch bundle=\(Bundle.main.bundlePath) pid=\(ProcessInfo.processInfo.processIdentifier)")
        Log.write("launch axTrusted=\(AX.isTrusted(prompt: false))")
        startWhenPermitted()
        Log.write("launch tapRunning=\(monitor.isRunning)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Permission

    /// Waits for Accessibility access by repeatedly *trying to do the thing*,
    /// rather than by asking whether we are allowed to.
    ///
    /// `AXIsProcessTrusted` caches its answer for the lifetime of the process.
    /// An app that was already running when the user ticked the box therefore
    /// keeps being told it is untrusted forever, and polling that API polls a
    /// value that can never change — the app looks broken until it is
    /// relaunched. Creating the event tap is the capability itself, so it
    /// cannot disagree with reality.
    private func startWhenPermitted() {
        if monitor.start() { return }

        // Only ask once; the prompt is what opens System Settings for them.
        _ = AX.isTrusted(prompt: true)

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.permissionAttempts += 1
            guard self.monitor.start() else {
                // Once a second forever would be noise; every fifth attempt is
                // enough to see whether the state ever changes.
                if self.permissionAttempts % 5 == 0 {
                    Log.write("waiting attempt=\(self.permissionAttempts) axTrusted=\(AX.isTrusted(prompt: false)) tapRunning=false")
                }
                return
            }
            Log.write("tap started after \(self.permissionAttempts) attempt(s)")
            timer.invalidate()
            self.permissionTimer = nil
        }
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

        // Report what is actually true — whether the tap is live — not what the
        // cached permission API claims.
        if !monitor.isRunning {
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
