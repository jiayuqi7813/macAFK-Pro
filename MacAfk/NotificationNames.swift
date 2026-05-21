import Foundation

extension Notification.Name {
    static let appModelStateChanged = Notification.Name("AppModelStateChanged")
    static let updateStatusChanged = Notification.Name("UpdateStatusChanged")
    static let launchAtLoginFailed = Notification.Name("LaunchAtLoginFailed")
    static let showPreferencesRequested = Notification.Name("ShowPreferencesRequested")
}
