import Foundation
import AppKit
import os

/// 辅助功能权限管理器
class AccessibilityPermissionManager {

    static let shared = AccessibilityPermissionManager()

    static let skipPermissionPromptsKey = "app.debug.skipPermissionPrompts"

    private var hasShownGuideAlert = false

    private init() {}

    /// Debug 模式：跳过系统权限弹窗与自定义引导弹窗
    var skipPermissionPrompts: Bool {
        UserDefaults.standard.bool(forKey: Self.skipPermissionPromptsKey)
    }

    /// 静默检查，绝不触发系统权限弹窗
    func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// 用户主动请求时触发系统权限提示（如点击「授予权限」）
    func promptSystemAccessibilityPermission() {
        guard !skipPermissionPrompts else {
            debugLog("Skipping system accessibility prompt (debug mode)", logger: AppLog.permissions)
            return
        }
        guard !checkAccessibilityPermission() else { return }

        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        debugLog("Triggered system accessibility prompt", logger: AppLog.permissions)
    }

    /// 启动时引导用户去系统设置，不触发系统权限弹窗，且每会话最多一次
    func showAccessibilityPermissionGuideIfNeeded() {
        guard !skipPermissionPrompts else {
            debugLog("Skipping accessibility permission guide (debug mode)", logger: AppLog.permissions)
            return
        }
        guard !checkAccessibilityPermission() else { return }
        guard !hasShownGuideAlert else { return }
        hasShownGuideAlert = true

        debugLog("Showing accessibility permission guide", logger: AppLog.permissions)

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("permission.accessibility.title", comment: "")
            alert.informativeText = NSLocalizedString("permission.accessibility.message", comment: "")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("permission.open_settings", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("button.cancel", comment: ""))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// 监控权限状态变化；授权成功后自动停止轮询
    @discardableResult
    func startMonitoringPermission(onChange: @escaping (Bool) -> Void) -> Timer? {
        var lastStatus = checkAccessibilityPermission()
        if lastStatus {
            onChange(true)
            return nil
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let currentStatus = self.checkAccessibilityPermission()
            if currentStatus != lastStatus {
                debugLog("Accessibility permission changed: \(lastStatus) -> \(currentStatus)", logger: AppLog.permissions)
                lastStatus = currentStatus
                onChange(currentStatus)
                if currentStatus {
                    timer.invalidate()
                }
            }
        }
        return timer
    }
}
