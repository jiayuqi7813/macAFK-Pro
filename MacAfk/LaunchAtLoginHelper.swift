import Foundation
import ServiceManagement
import os

/// 管理应用开机自启动功能
enum LaunchAtLoginHelper {

    /// 设置开机自启动
    /// - Returns: 是否成功
    @discardableResult
    static func setLaunchAtLogin(enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                debugLog("Launch at login enabled", logger: AppLog.launchAtLogin)
            } else {
                try SMAppService.mainApp.unregister()
                debugLog("Launch at login disabled", logger: AppLog.launchAtLogin)
            }
            return true
        } catch {
            AppLog.launchAtLogin.error("Failed to set launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 检查当前是否已设置开机自启动
    static func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
