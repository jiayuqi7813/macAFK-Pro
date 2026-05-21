import Foundation
import Carbon
import AppKit
import Combine
import ApplicationServices

enum ShortcutAction: Hashable, Codable {
    case toggleJiggle
    case toggleBrightness
    case increaseJiggleInterval
    case decreaseJiggleInterval
}

struct ShortcutConfig: Codable, Equatable {
    let action: ShortcutAction
    let keyCode: UInt16
    let modifiers: UInt
    let displayName: String

    init(action: ShortcutAction, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, displayName: String) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.displayName = displayName
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        var parts: [String] = []

        let flags = modifierFlags
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }

        parts.append(Self.keyCodeToChar(keyCode))
        return parts.joined(separator: " ")
    }

    static func keyCodeToChar(_ code: UInt16) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 17: return "T"
        case 16: return "Y"
        case 32: return "U"
        case 34: return "I"
        case 31: return "O"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 36: return "↩"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "\(code)"
        }
    }
}

class ShortcutManager: ObservableObject {
    var onAction: ((ShortcutAction) -> Void)?

    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private let userDefaultsKey = "customShortcuts"

    /// 全局快捷键监听是否已建立（无辅助功能权限时为 false）
    private(set) var isGlobalMonitorActive = false

    @Published var shortcuts: [ShortcutAction: ShortcutConfig] = [
        .toggleJiggle: ShortcutConfig(
            action: .toggleJiggle,
            keyCode: 1,
            modifiers: [.command, .control],
            displayName: NSLocalizedString("shortcut.toggle_jiggle", comment: "")
        ),
        .toggleBrightness: ShortcutConfig(
            action: .toggleBrightness,
            keyCode: 11,
            modifiers: [.command, .control],
            displayName: NSLocalizedString("shortcut.toggle_brightness", comment: "")
        ),
        .increaseJiggleInterval: ShortcutConfig(
            action: .increaseJiggleInterval,
            keyCode: 126,
            modifiers: [.command, .control],
            displayName: NSLocalizedString("shortcut.increase_interval", comment: "")
        ),
        .decreaseJiggleInterval: ShortcutConfig(
            action: .decreaseJiggleInterval,
            keyCode: 125,
            modifiers: [.command, .control],
            displayName: NSLocalizedString("shortcut.decrease_interval", comment: "")
        )
    ]

    init() {
        loadCustomShortcuts()
    }

    @discardableResult
    func startListening() -> Bool {
        stopListening()

        let hasPermission = AccessibilityPermissionManager.shared.checkAccessibilityPermission()

        if hasPermission {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleEvent(event)
            }
            isGlobalMonitorActive = eventMonitor != nil
        } else {
            isGlobalMonitorActive = false
            debugLog("Accessibility permission missing for global shortcuts", logger: AppLog.shortcuts)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        debugLog(
            "Shortcut listening started (global: \(self.isGlobalMonitorActive))",
            logger: AppLog.shortcuts
        )
        return isGlobalMonitorActive
    }

    func stopListening() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        isGlobalMonitorActive = false
        debugLog("Shortcut listening stopped", logger: AppLog.shortcuts)
    }

    /// 辅助功能权限就绪后重建全局监听
    func restartGlobalMonitorIfNeeded() {
        guard AccessibilityPermissionManager.shared.checkAccessibilityPermission() else { return }
        guard !isGlobalMonitorActive else { return }

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        isGlobalMonitorActive = eventMonitor != nil
        debugLog(
            "Global shortcut monitor restarted (active: \(self.isGlobalMonitorActive))",
            logger: AppLog.shortcuts
        )
    }

    private func handleEvent(_ event: NSEvent) {
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

        for (action, config) in shortcuts {
            let configModifiers = config.modifierFlags.intersection([.command, .control, .option, .shift])

            if event.keyCode == config.keyCode && eventModifiers == configModifiers {
                debugLog("Shortcut triggered: \(String(describing: action))", logger: AppLog.shortcuts)
                onAction?(action)
                break
            }
        }
    }

    func getShortcutDisplay(for action: ShortcutAction) -> String {
        shortcuts[action]?.displayString ?? NSLocalizedString("shortcut.editor.not_set", comment: "")
    }

    func findConflict(
        for action: ShortcutAction,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> ShortcutAction? {
        let configModifiers = modifiers.intersection([.command, .control, .option, .shift])

        for (otherAction, config) in shortcuts where otherAction != action {
            let otherModifiers = config.modifierFlags.intersection([.command, .control, .option, .shift])
            if config.keyCode == keyCode && otherModifiers == configModifiers {
                return otherAction
            }
        }
        return nil
    }

    @discardableResult
    func updateShortcut(
        for action: ShortcutAction,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> ShortcutAction? {
        if let conflict = findConflict(for: action, keyCode: keyCode, modifiers: modifiers) {
            return conflict
        }

        if let existing = shortcuts[action] {
            shortcuts[action] = ShortcutConfig(
                action: action,
                keyCode: keyCode,
                modifiers: modifiers,
                displayName: existing.displayName
            )
            saveCustomShortcuts()
        }
        return nil
    }

    func resetToDefaults() {
        shortcuts = [
            .toggleJiggle: ShortcutConfig(
                action: .toggleJiggle,
                keyCode: 1,
                modifiers: [.command, .control],
                displayName: NSLocalizedString("shortcut.toggle_jiggle", comment: "")
            ),
            .toggleBrightness: ShortcutConfig(
                action: .toggleBrightness,
                keyCode: 11,
                modifiers: [.command, .control],
                displayName: NSLocalizedString("shortcut.toggle_brightness", comment: "")
            ),
            .increaseJiggleInterval: ShortcutConfig(
                action: .increaseJiggleInterval,
                keyCode: 126,
                modifiers: [.command, .control],
                displayName: NSLocalizedString("shortcut.increase_interval", comment: "")
            ),
            .decreaseJiggleInterval: ShortcutConfig(
                action: .decreaseJiggleInterval,
                keyCode: 125,
                modifiers: [.command, .control],
                displayName: NSLocalizedString("shortcut.decrease_interval", comment: "")
            )
        ]
        saveCustomShortcuts()
    }

    private func saveCustomShortcuts() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(shortcuts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            debugLog("Saved custom shortcuts", logger: AppLog.shortcuts)
        }
    }

    private func loadCustomShortcuts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([ShortcutAction: ShortcutConfig].self, from: data) {
                shortcuts = decoded
                debugLog("Loaded custom shortcuts", logger: AppLog.shortcuts)
                return
            }
        }
        debugLog("Using default shortcut configuration", logger: AppLog.shortcuts)
    }
}
