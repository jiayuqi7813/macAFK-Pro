import Foundation
import AppKit
import os

enum AppUpdateInstaller {

    static let preferredInstallLocationKey = "app.preferredInstallLocation"
    private static let appName = "MacAfk Pro.app"

    enum InstallError: LocalizedError {
        case mountFailed(String)
        case appNotFoundInDMG
        case stagingFailed(String)
        case targetNotWritable(String)
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .mountFailed(let detail):
                return "update.error.mount".localized + ": \(detail)"
            case .appNotFoundInDMG:
                return "update.error.app_not_found".localized
            case .stagingFailed(let detail):
                return "update.error.staging".localized + ": \(detail)"
            case .targetNotWritable(let path):
                return String(format: "update.error.target_not_writable".localized, path)
            case .scriptFailed(let detail):
                return "update.error.install_script".localized + ": \(detail)"
            }
        }
    }

    /// 记录安装位置，后续更新原地替换以继承 TCC 权限
    static func recordCurrentInstallLocationIfNeeded() {
        let current = Bundle.main.bundleURL
        if current.path.hasPrefix("/Applications/") || current.path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            UserDefaults.standard.set(current.path, forKey: preferredInstallLocationKey)
            debugLog("Recorded install location: \(current.path)", logger: AppLog.installer)
        }
    }

    /// 优先使用已记录的安装路径，确保更新后权限可继承
    static func preferredInstallURL() -> URL {
        if let saved = UserDefaults.standard.string(forKey: preferredInstallLocationKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved)
        }

        let current = Bundle.main.bundleURL
        if current.path.hasPrefix("/Applications/") || current.path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return current
        }

        let applications = URL(fileURLWithPath: "/Applications/\(appName)")
        if FileManager.default.fileExists(atPath: applications.path) {
            return applications
        }

        return applications
    }

    static func installFromDMG(at dmgURL: URL) throws {
        let mountPoint = try mountDMG(at: dmgURL)
        defer { unmountDMG(at: mountPoint) }

        let sourceApp = try findAppBundle(in: mountPoint)
        let stagedApp = try stageAppBundle(from: sourceApp)
        let targetURL = preferredInstallURL()

        let parent = targetURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw InstallError.targetNotWritable(parent.path)
        }

        UserDefaults.standard.set(targetURL.path, forKey: preferredInstallLocationKey)
        try scheduleReplaceAndRelaunch(stagedApp: stagedApp, targetURL: targetURL)
        debugLog("Scheduled in-place update to \(targetURL.path)", logger: AppLog.installer)
    }

    private static func mountDMG(at dmgURL: URL) throws -> URL {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", "-nobrowse", "-readonly", "-plist", dmgURL.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw InstallError.mountFailed("hdiutil exit \(task.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw InstallError.mountFailed("invalid plist")
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint)
            }
        }

        throw InstallError.mountFailed("mount-point not found")
    }

    private static func unmountDMG(at mountPoint: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", mountPoint.path, "-quiet"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func findAppBundle(in mountPoint: URL) throws -> URL {
        let fileManager = FileManager.default
        let candidates = try fileManager.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if let app = candidates.first(where: { $0.pathExtension == "app" && $0.lastPathComponent.contains("MacAfk") }) {
            return app
        }

        if let app = candidates.first(where: { $0.pathExtension == "app" }) {
            return app
        }

        throw InstallError.appNotFoundInDMG
    }

    private static func stageAppBundle(from source: URL) throws -> URL {
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent("MacAfkUpdate-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = stagingRoot.appendingPathComponent(source.lastPathComponent, isDirectory: true)

        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: stagedApp)
        return stagedApp
    }

    private static func scheduleReplaceAndRelaunch(stagedApp: URL, targetURL: URL) throws {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory.appendingPathComponent("macafk-update-\(UUID().uuidString).sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        let stagedPath = stagedApp.path
        let targetPath = targetURL.path
        let parentPath = targetURL.deletingLastPathComponent().path

        let script = """
        #!/bin/bash
        set -e
        PID=\(pid)
        STAGED="\(stagedPath)"
        TARGET="\(targetPath)"
        PARENT="\(parentPath)"

        for _ in $(seq 1 60); do
          if ! kill -0 "$PID" 2>/dev/null; then
            break
          fi
          sleep 0.5
        done

        mkdir -p "$PARENT"
        rm -rf "$TARGET"
        /usr/bin/ditto "$STAGED" "$TARGET"
        /usr/bin/xattr -cr "$TARGET" 2>/dev/null || true
        /usr/bin/open "$TARGET"
        rm -rf "$(dirname "$STAGED")"
        rm -f "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        try launcher.run()

        guard launcher.terminationStatus == 0 || launcher.isRunning else {
            throw InstallError.scriptFailed("launcher exit \(launcher.terminationStatus)")
        }
    }
}
