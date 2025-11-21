import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appModel = AppModel()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sleep", accessibilityDescription: "MacAfk")
            button.action = #selector(toggleMenu)
        }
        
        // Create the menu
        constructMenu()
    }
    
    @objc func toggleMenu() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        let statusTitle = appModel.isJiggling ? "Stop Jiggling" : "Start Jiggling"
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleJiggler), keyEquivalent: "S")
        menu.addItem(toggleItem)
        
        let brightnessItem = NSMenuItem(title: "Low Brightness Mode", action: #selector(toggleBrightness), keyEquivalent: "B")
        brightnessItem.state = appModel.isLowBrightness ? .on : .off
        menu.addItem(brightnessItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Main Window", action: #selector(showMainWindow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
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
        
        menu.items[0].title = appModel.isJiggling ? "Stop Jiggling" : "Start Jiggling"
        menu.items[1].state = appModel.isLowBrightness ? .on : .off
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: appModel.isJiggling ? "sleep.circle.fill" : "sleep", accessibilityDescription: "MacAfk")
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
