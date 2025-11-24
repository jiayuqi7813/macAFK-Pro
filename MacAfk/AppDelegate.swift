import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appModel = AppModel()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 隐藏 Dock 图标，只在状态栏显示
        NSApp.setActivationPolicy(.accessory)
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sleep", accessibilityDescription: "MacAfk Pro")
            button.action = #selector(toggleMenu)
        }
        
        // Create the menu
        constructMenu()
    }
    
    // 关闭窗口后不退出应用，继续在后台运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    @objc func toggleMenu() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        let statusTitle = appModel.isJiggling ? NSLocalizedString("menu.stop_jiggling", comment: "") : NSLocalizedString("menu.start_jiggling", comment: "")
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleJiggler), keyEquivalent: "S")
        menu.addItem(toggleItem)
        
        let brightnessItem = NSMenuItem(title: NSLocalizedString("settings.low_brightness_mode", comment: ""), action: #selector(toggleBrightness), keyEquivalent: "B")
        brightnessItem.state = appModel.isLowBrightness ? .on : .off
        menu.addItem(brightnessItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.show_main_window", comment: ""), action: #selector(showMainWindow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("button.quit", comment: ""), action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // Observe changes to update menu
        // In a real app we'd use Combine to update the menu item titles.
        // For now, we'll just rebuild or update on action.
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
        
        menu.items[0].title = appModel.isJiggling ? NSLocalizedString("menu.stop_jiggling", comment: "") : NSLocalizedString("menu.start_jiggling", comment: "")
        menu.items[1].state = appModel.isLowBrightness ? .on : .off
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: appModel.isJiggling ? "sleep.circle.fill" : "sleep", accessibilityDescription: "MacAfk Pro")
        }
    }
    
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
