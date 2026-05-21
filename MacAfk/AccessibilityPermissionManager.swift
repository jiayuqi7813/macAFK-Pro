import Foundation
import AppKit
import os

/// 辅助功能权限管理器
class AccessibilityPermissionManager {

    static let shared = AccessibilityPermissionManager()

    static let skipPermissionPromptsKey = "app.debug.skipPermissionPrompts"

    private var permissionMonitorTimer: Timer?

    private init() {}

    /// Debug 模式：跳过系统权限弹窗与自定义引导弹窗
    var skipPermissionPrompts: Bool {
        UserDefaults.standard.bool(forKey: Self.skipPermissionPromptsKey)
    }

    /// 当前运行实例的路径，用于引导用户授权正确的二进制
    var runningAppPath: String {
        Bundle.main.bundlePath
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

    /// 打开系统设置并将当前实例注册到辅助功能列表
    func openAccessibilitySettings() {
        promptSystemAccessibilityPermission()

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 请求展示权限检查页面（由 AppDelegate 呈现）
    func requestPermissionCheckPresentation() {
        guard !skipPermissionPrompts else { return }
        guard !checkAccessibilityPermission() else { return }

        debugLog("Requesting permission check presentation", logger: AppLog.permissions)
        NotificationCenter.default.post(name: .showPermissionCheckRequested, object: nil)
    }

    /// 启动时引导：展示权限检查页面，不再使用 NSAlert
    func showAccessibilityPermissionGuideIfNeeded() {
        requestPermissionCheckPresentation()
    }

    /// 监控权限状态变化；授权成功后自动停止轮询
    @discardableResult
    func startMonitoringPermission(onChange: @escaping (Bool) -> Void) -> Timer? {
        stopMonitoringPermission()

        var lastStatus = checkAccessibilityPermission()
        if lastStatus {
            onChange(true)
            return nil
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
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
                    self.permissionMonitorTimer = nil
                    NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionMonitorTimer = timer
        return timer
    }

    func stopMonitoringPermission() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }
}
