import Foundation
import os

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.snowywar.MacAfk"

    static let appModel = Logger(subsystem: subsystem, category: "AppModel")
    static let jiggler = Logger(subsystem: subsystem, category: "Jiggler")
    static let brightness = Logger(subsystem: subsystem, category: "Brightness")
    static let betterDisplay = Logger(subsystem: subsystem, category: "BetterDisplay")
    static let shortcuts = Logger(subsystem: subsystem, category: "Shortcuts")
    static let launchAtLogin = Logger(subsystem: subsystem, category: "LaunchAtLogin")
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
    static let updates = Logger(subsystem: subsystem, category: "Updates")
    static let appDelegate = Logger(subsystem: subsystem, category: "AppDelegate")
    static let agentHooks = Logger(subsystem: subsystem, category: "AgentHooks")
    static let installer = Logger(subsystem: subsystem, category: "Installer")
}

#if DEBUG
func debugLog(_ message: @autoclosure () -> String, logger: Logger) {
    let text = message()
    logger.debug("\(text, privacy: .public)")
}
#else
func debugLog(_ message: @autoclosure () -> String, logger: Logger) {}
#endif
