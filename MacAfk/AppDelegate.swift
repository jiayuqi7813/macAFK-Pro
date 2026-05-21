import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum MenuItemTag: Int {
        case toggleJiggle = 1
        case lowBrightness = 2
    }

    var statusItem: NSStatusItem!
    var appModel = AppModel()
    private let languageManager = LanguageManager.shared
    private let updateManager = UpdateManager.shared
    private let permissionManager = AccessibilityPermissionManager.shared
    private var mainWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var permissionMonitorTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateIfAnotherInstanceIsRunning()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        handleAccessibilityPermissionOnLaunch()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = loadMenuBarIcon(isActive: false)
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        constructMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStatus),
            name: .updateStatusChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appModelStateChanged),
            name: .appModelStateChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowPreferencesRequested),
            name: .showPreferencesRequested,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else if event.type == .leftMouseUp {
            toggleJiggler()
        }
    }

    @objc func showMenu() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func constructMenu() {
        let menu = NSMenu()

        let statusTitle = appModel.isJiggling
            ? languageManager.localizedString(for: "menu.stop_jiggling")
            : languageManager.localizedString(for: "menu.start_jiggling")
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleJiggler), keyEquivalent: "S")
        toggleItem.tag = MenuItemTag.toggleJiggle.rawValue
        menu.addItem(toggleItem)

        let brightnessItem = NSMenuItem(
            title: languageManager.localizedString(for: "settings.low_brightness_mode"),
            action: #selector(toggleBrightness),
            keyEquivalent: "B"
        )
        brightnessItem.tag = MenuItemTag.lowBrightness.rawValue
        brightnessItem.state = appModel.isLowBrightness ? .on : .off
        menu.addItem(brightnessItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "menu.show_main_window"), action: #selector(showMainWindow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "menu.preferences"), action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "update.check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "button.quit"), action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        updateMenuBarIcon()
    }

    @objc func toggleJiggler() {
        appModel.toggleJiggle()
        updateMenu()
    }

    @objc func toggleBrightness() {
        appModel.toggleBrightnessMode()
        updateMenu()
    }

    func updateMenu() {
        guard let menu = statusItem.menu else { return }

        if let toggleItem = menu.item(withTag: MenuItemTag.toggleJiggle.rawValue) {
            toggleItem.title = appModel.isJiggling
                ? languageManager.localizedString(for: "menu.stop_jiggling")
                : languageManager.localizedString(for: "menu.start_jiggling")
        }

        if let brightnessItem = menu.item(withTag: MenuItemTag.lowBrightness.rawValue) {
            brightnessItem.state = appModel.isLowBrightness ? .on : .off
        }

        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        if let button = statusItem.button {
            button.image = loadMenuBarIcon(isActive: appModel.isJiggling)
        }
    }

    @objc func languageDidChange() {
        constructMenu()
        syncWindowTitles()
    }

    @objc func appModelStateChanged() {
        updateMenu()
    }

    @objc func checkForUpdates() {
        updateManager.checkForUpdates(silent: false)
    }

    @objc func handleUpdateStatus() {
        if case .available = updateManager.updateStatus {
            showMainWindow()
        }
    }

    @objc func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        createMainWindow()
    }

    @objc func showPreferences() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = preferencesWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        createPreferencesWindow()
    }

    @objc private func handleShowPreferencesRequested(_ notification: Notification) {
        showPreferences()
    }

    private func configureStandardWindow(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.isMovableByWindowBackground = true
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    private func createMainWindow() {
        let contentView = ContentView(appModel: appModel)
            .environmentObject(languageManager)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = languageManager.localizedString(for: "app.name")
        configureStandardWindow(window)
        window.setFrameAutosaveName("MainWindow")
        configureMainWindowSize(window)

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func createPreferencesWindow() {
        let contentView = NewPreferencesView()
            .environmentObject(languageManager)
            .environmentObject(appModel)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = languageManager.localizedString(for: "settings.window_title")
        configureStandardWindow(window)
        window.titleVisibility = .hidden
        window.setFrameAutosaveName("PreferencesWindow")
        configurePreferencesWindowSize(window)

        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func configureMainWindowSize(_ window: NSWindow) {
        let minimumSize = NSSize(width: 480, height: 620)
        let idealSize = NSSize(width: 480, height: 640)
        let maximumSize = NSSize(width: 520, height: 700)

        window.contentMinSize = minimumSize
        window.contentMaxSize = maximumSize

        let currentSize = window.contentLayoutRect.size
        if currentSize.width < minimumSize.width
            || currentSize.height < minimumSize.height
            || currentSize.width > idealSize.width
            || currentSize.height > idealSize.height {
            window.setContentSize(idealSize)
            window.center()
        }
    }

    private func configurePreferencesWindowSize(_ window: NSWindow) {
        let minimumSize = NSSize(width: 900, height: 560)
        let idealSize = NSSize(width: 1_180, height: 720)
        let maximumSize = NSSize(width: 1_520, height: 980)

        window.contentMinSize = minimumSize
        window.contentMaxSize = maximumSize

        let currentSize = window.contentLayoutRect.size
        if currentSize.width < minimumSize.width
            || currentSize.height < minimumSize.height
            || currentSize.width > maximumSize.width
            || currentSize.height > maximumSize.height {
            window.setContentSize(idealSize)
            window.center()
        }
    }

    private func syncWindowTitles() {
        mainWindow?.title = languageManager.localizedString(for: "app.name")
        preferencesWindow?.title = languageManager.localizedString(for: "settings.window_title")
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func terminateIfAnotherInstanceIsRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }

        guard !otherInstances.isEmpty else { return }

        debugLog("Another instance is already running, terminating duplicate", logger: AppLog.appDelegate)
        otherInstances.forEach { $0.activate(options: []) }
        NSApp.terminate(nil)
    }

    private func handleAccessibilityPermissionOnLaunch() {
        guard !permissionManager.skipPermissionPrompts else {
            debugLog("Skipping launch accessibility guide (debug mode)", logger: AppLog.appDelegate)
            return
        }
        guard !permissionManager.checkAccessibilityPermission() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            guard !self.permissionManager.checkAccessibilityPermission() else { return }

            debugLog("Accessibility permission missing, showing guide", logger: AppLog.appDelegate)
            self.permissionManager.showAccessibilityPermissionGuideIfNeeded()

            self.permissionMonitorTimer?.invalidate()
            self.permissionMonitorTimer = self.permissionManager.startMonitoringPermission { [weak self] granted in
                guard let self, granted else { return }

                debugLog("Accessibility granted, restarting shortcut listener", logger: AppLog.appDelegate)
                DispatchQueue.main.async {
                    self.permissionMonitorTimer?.invalidate()
                    self.permissionMonitorTimer = nil
                    self.appModel.shortcutManager.stopListening()
                    self.appModel.shortcutManager.startListening()
                }
            }
        }
    }

    private func loadMenuBarIcon(isActive: Bool) -> NSImage? {
        let iconName = isActive ? "menubar-active" : "menubar-idle"

        guard let image = NSImage(named: iconName) else {
            return NSImage(systemSymbolName: isActive ? "sleep.circle.fill" : "sleep", accessibilityDescription: "MacAfk Pro")
        }

        image.size = NSSize(width: 24, height: 24)
        return image
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window == mainWindow || window == preferencesWindow else { return }

        if window == mainWindow {
            mainWindow = nil
        } else if window == preferencesWindow {
            preferencesWindow = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let visibleWindows = NSApp.windows.filter { window in
                window.isVisible && window.canBecomeKey && !window.className.contains("StatusBar")
            }

            if visibleWindows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
                debugLog("All windows closed, running in background", logger: AppLog.appDelegate)
            }
        }
    }
}
