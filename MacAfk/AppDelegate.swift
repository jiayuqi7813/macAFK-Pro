import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appModel = AppModel()
    private let languageManager = LanguageManager.shared
    private let updateManager = UpdateManager.shared
    private let permissionManager = AccessibilityPermissionManager.shared
    private var mainWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 初始状态：隐藏 Dock 图标，只在状态栏显示
        // 使用 .accessory 而不是 .prohibited，这样可以接收全局事件
        NSApp.setActivationPolicy(.accessory)
        
        // 检查并请求辅助功能权限
        checkAndRequestAccessibilityPermission()
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = loadMenuBarIcon(isActive: false)
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create the menu (不自动弹出)
        constructMenu()
        
        // 监听语言切换事件，更新菜单
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageChanged,
            object: nil
        )
        
        // 监听更新状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStatus),
            name: NSNotification.Name("UpdateStatusChanged"),
            object: nil
        )
        
        // 监听 AppModel 状态变化，实时更新菜单栏图标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appModelStateChanged),
            name: NSNotification.Name("AppModelStateChanged"),
            object: nil
        )
    }
    
    // 关闭窗口后不退出应用，继续在后台运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键点击：显示菜单
            showMenu()
        } else if event.type == .leftMouseUp {
            // 左键点击：切换运行状态
            toggleJiggler()
        }
    }
    
    @objc func showMenu() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        let statusTitle = appModel.isJiggling ? languageManager.localizedString(for: "menu.stop_jiggling") : languageManager.localizedString(for: "menu.start_jiggling")
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleJiggler), keyEquivalent: "S")
        menu.addItem(toggleItem)
        
        let brightnessItem = NSMenuItem(title: languageManager.localizedString(for: "settings.low_brightness_mode"), action: #selector(toggleBrightness), keyEquivalent: "B")
        brightnessItem.state = appModel.isLowBrightness ? .on : .off
        menu.addItem(brightnessItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "menu.show_main_window"), action: #selector(showMainWindow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "menu.preferences"), action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "update.check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: languageManager.localizedString(for: "button.quit"), action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
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
        
        menu.items[0].title = appModel.isJiggling ? languageManager.localizedString(for: "menu.stop_jiggling") : languageManager.localizedString(for: "menu.start_jiggling")
        menu.items[1].state = appModel.isLowBrightness ? .on : .off
        
        if let button = statusItem.button {
            button.image = loadMenuBarIcon(isActive: appModel.isJiggling)
        }
    }
    
    @objc func languageDidChange() {
        // 语言切换时重新构建菜单
        constructMenu()
    }
    
    @objc func appModelStateChanged() {
        // AppModel 状态改变时更新菜单和图标
        updateMenu()
    }
    
    @objc func checkForUpdates() {
        updateManager.checkForUpdates(silent: false)
    }
    
    @objc func handleUpdateStatus() {
        // 当发现更新时，显示主窗口
        if case .available = updateManager.updateStatus {
            showMainWindow()
        }
    }
    
    @objc func showMainWindow() {
        // 显示窗口前，将激活策略改为 regular，以便显示 Dock 图标和菜单栏
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // 如果已有主窗口，显示它
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // 创建新的主窗口
        createMainWindow()
    }
    
    @objc func showPreferences() {
        // 显示窗口前，将激活策略改为 regular，以便显示 Dock 图标和菜单栏
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // 如果已有设置窗口，显示它
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // 创建新的设置窗口
        createPreferencesWindow()
    }
    
    private func createMainWindow() {
        // 创建 SwiftUI 主视图
        let contentView = ContentView(appModel: appModel)
            .environmentObject(languageManager)
        
        // 创建托管窗口
        let hostingController = NSHostingController(rootView: contentView)
        
        // 创建窗口
        let window = NSWindow(contentViewController: hostingController)
        window.title = languageManager.localizedString(for: "app.name")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false // 窗口关闭时不释放
        window.center()
        window.setFrameAutosaveName("MainWindow")
        
        // 设置窗口代理以监听关闭事件
        window.delegate = self
        
        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    private func createPreferencesWindow() {
        // 创建 SwiftUI 设置视图
        let contentView = NewPreferencesView()
            .environmentObject(languageManager)
            .environmentObject(appModel)
        
        // 创建托管窗口
        let hostingController = NSHostingController(rootView: contentView)
        
        // 创建窗口
        let window = NSWindow(contentViewController: hostingController)
        window.title = languageManager.localizedString(for: "menu.preferences")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false // 窗口关闭时不释放
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        
        // 设置窗口代理以监听关闭事件
        window.delegate = self
        
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Accessibility Permission
    
    private func checkAndRequestAccessibilityPermission() {
        // 延迟检查，确保应用完全启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            if !self.permissionManager.checkAccessibilityPermission() {
                print("⚠️ [AppDelegate] 未检测到辅助功能权限，正在请求...")
                self.permissionManager.requestAccessibilityPermission()
                
                // 监控权限状态变化
                self.permissionManager.startMonitoringPermission { granted in
                    if granted {
                        print("✅ [AppDelegate] 辅助功能权限已授予，重启快捷键监听...")
                        // 重启快捷键监听
                        DispatchQueue.main.async {
                            self.appModel.shortcutManager.stopListening()
                            self.appModel.shortcutManager.startListening()
                        }
                    }
                }
            } else {
                print("✅ [AppDelegate] 辅助功能权限已授予")
            }
        }
    }
    
    // MARK: - Menu Bar Icon
    
    private func loadMenuBarIcon(isActive: Bool) -> NSImage? {
        let iconName = isActive ? "menubar-active" : "menubar-idle"
        
        // 从 Asset Catalog 加载图标
        guard let image = NSImage(named: iconName) else {
            // 如果加载失败，使用系统图标作为后备
            print("⚠️ 无法加载图标: \(iconName)")
            return NSImage(systemSymbolName: isActive ? "sleep.circle.fill" : "sleep", accessibilityDescription: "MacAfk Pro")
        }
        
        // Asset Catalog 中已设置为 template，这里设置尺寸
        image.size = NSSize(width: 24, height: 24)
        
        return image
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 处理我们的主窗口或设置窗口
        guard let window = notification.object as? NSWindow else {
            return
        }
        
        // 检查是否是我们管理的窗口
        guard window == mainWindow || window == preferencesWindow else {
            return
        }
        
        // 延迟检查，确保窗口关闭事件完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // 检查是否还有可见的应用窗口（不包括菜单等系统窗口）
            let visibleWindows = NSApp.windows.filter { window in
                window.isVisible && window.canBecomeKey && !window.className.contains("StatusBar")
            }
            
            if visibleWindows.isEmpty {
                // 所有窗口关闭后，隐藏 Dock 图标，但保持 accessory 状态以接收全局事件
                NSApp.setActivationPolicy(.accessory)
                
                // 确保快捷键监听器仍然活跃
                print("ℹ️ [AppDelegate] 所有窗口已关闭，应用在后台运行，快捷键监听保持活跃")
            }
        }
    }
}
