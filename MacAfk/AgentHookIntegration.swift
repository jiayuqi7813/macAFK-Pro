import Foundation
import os

struct AgentHookInstallSummary: Equatable {
    static let supportedSources = ["codex", "claude", "qoder", "qwen", "factory", "codebuddy", "cursor", "gemini", "kimi"]

    var installedSources: [String] = []
    var supportedSources: [String] = Self.supportedSources

    var installedCount: Int { installedSources.count }
    var supportedCount: Int { supportedSources.count }
    var hasAnyInstalled: Bool { !installedSources.isEmpty }
}

final class AgentHookMonitor {
    private let fileManager: FileManager
    private let inboxURL: URL
    private let helperScriptURL: URL
    private var timer: Timer?
    private var onEvent: ((AgentHookEvent) -> Void)?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacAfk", isDirectory: true)
        self.inboxURL = baseURL.appendingPathComponent("AgentHooks/inbox", isDirectory: true)
        self.helperScriptURL = baseURL.appendingPathComponent("bin/macafk-agent-hook", isDirectory: false)
    }

    func start(onEvent: @escaping (AgentHookEvent) -> Void) {
        self.onEvent = onEvent
        do {
            _ = try ensureHelperScript()
        } catch {
            AppLog.agentHooks.error("Failed to prepare hook helper: \(error.localizedDescription, privacy: .public)")
        }
        pollInbox()

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollInbox()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onEvent = nil
    }

    @discardableResult
    func ensureHelperScript() throws -> URL {
        try fileManager.createDirectory(
            at: helperScriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let script = Self.helperScript
        if (try? String(contentsOf: helperScriptURL, encoding: .utf8)) != script {
            try script.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScriptURL.path)
        return helperScriptURL
    }

    private func pollInbox() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let eventFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in eventFiles {
            processEventFile(url)
        }
    }

    private func processEventFile(_ url: URL) {
        defer {
            try? fileManager.removeItem(at: url)
        }

        guard let data = try? Data(contentsOf: url),
              let event = AgentHookEventParser.parseEnvelope(data: data, fallbackID: url.deletingPathExtension().lastPathComponent) else {
            return
        }

        onEvent?(event)
    }

    private static let helperScript = """
#!/bin/zsh
set +e

source_name="unknown"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      source_name="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

inbox_dir="${MACAFK_AGENT_HOOK_DIR:-$HOME/Library/Application Support/MacAfk/AgentHooks/inbox}"
/bin/mkdir -p "$inbox_dir" >/dev/null 2>&1 || exit 0

payload="$(/bin/cat | /usr/bin/base64 | /usr/bin/tr -d '\\n')" || exit 0
timestamp="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
tmp_file="$(/usr/bin/mktemp "$inbox_dir/event.XXXXXX")" || exit 0
final_file="$tmp_file.json"

/usr/bin/printf '{"source":"%s","timestamp":"%s","payloadBase64":"%s"}\\n' "$source_name" "$timestamp" "$payload" > "$tmp_file" || exit 0
/bin/mv "$tmp_file" "$final_file" >/dev/null 2>&1
exit 0
"""
}

enum AgentHookInstaller {
    private static let marker = "MacAfk Pro"
    private static let managedCommandNeedle = "macafk-agent-hook"
    private static let fileManager = FileManager.default
    private static var homeURL: URL { fileManager.homeDirectoryForCurrentUser }

    static func installAll(helperURL: URL) throws -> AgentHookInstallSummary {
        let helperPath = helperURL.standardizedFileURL.path

        try installCodex(command: hookCommand(helperPath, source: "codex"))
        try installClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".claude/settings.json"), command: hookCommand(helperPath, source: "claude"), source: "claude")
        try installClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".qoder/settings.json"), command: hookCommand(helperPath, source: "qoder"), source: "qoder")
        try installClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".qwen/settings.json"), command: hookCommand(helperPath, source: "qwen"), source: "qwen")
        try installClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".factory/settings.json"), command: hookCommand(helperPath, source: "factory"), source: "factory")
        try installClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".codebuddy/settings.json"), command: hookCommand(helperPath, source: "codebuddy"), source: "codebuddy")
        try installCursor(command: hookCommand(helperPath, source: "cursor"))
        try installGemini(command: hookCommand(helperPath, source: "gemini"))
        try installKimi(command: hookCommand(helperPath, source: "kimi"))

        return status()
    }

    static func uninstallAll() throws -> AgentHookInstallSummary {
        try uninstallCodex()
        try uninstallClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".claude/settings.json"))
        try uninstallClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".qoder/settings.json"))
        try uninstallClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".qwen/settings.json"))
        try uninstallClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".factory/settings.json"))
        try uninstallClaudeCompatible(settingsURL: homeURL.appendingPathComponent(".codebuddy/settings.json"))
        try uninstallCursor()
        try uninstallGemini()
        try uninstallKimi()
        return status()
    }

    static func status() -> AgentHookInstallSummary {
        let checks: [(String, URL)] = [
            ("codex", homeURL.appendingPathComponent(".codex/hooks.json")),
            ("claude", homeURL.appendingPathComponent(".claude/settings.json")),
            ("qoder", homeURL.appendingPathComponent(".qoder/settings.json")),
            ("qwen", homeURL.appendingPathComponent(".qwen/settings.json")),
            ("factory", homeURL.appendingPathComponent(".factory/settings.json")),
            ("codebuddy", homeURL.appendingPathComponent(".codebuddy/settings.json")),
            ("cursor", homeURL.appendingPathComponent(".cursor/hooks.json")),
            ("gemini", homeURL.appendingPathComponent(".gemini/settings.json")),
            ("kimi", homeURL.appendingPathComponent(".kimi/config.toml")),
        ]

        let installed = checks.compactMap { source, url -> String? in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return contents.contains(managedCommandNeedle) && contents.contains("--source \(source)") ? source : nil
        }

        return AgentHookInstallSummary(installedSources: installed)
    }

    private static func installCodex(command: String) throws {
        let codexDirectory = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let configURL = codexDirectory.appendingPathComponent("config.toml")

        try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try installGroupedJSONHooks(
            at: hooksURL,
            eventSpecs: [
                ("SessionStart", "startup|resume"),
                ("UserPromptSubmit", nil),
                ("Stop", nil),
            ],
            command: command,
            includeName: false
        )
        try enableCodexHooksFeature(at: configURL)
    }

    private static func uninstallCodex() throws {
        try uninstallGroupedJSONHooks(
            at: homeURL.appendingPathComponent(".codex/hooks.json"),
            eventNames: ["SessionStart", "UserPromptSubmit", "Stop"]
        )
    }

    private static func installClaudeCompatible(settingsURL: URL, command: String, source: String) throws {
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try installGroupedJSONHooks(
            at: settingsURL,
            eventSpecs: [
                ("SessionStart", nil),
                ("UserPromptSubmit", nil),
                ("Stop", nil),
                ("SessionEnd", nil),
                ("StopFailure", nil),
                ("SubagentStart", nil),
                ("SubagentStop", nil),
            ],
            command: command,
            includeName: false
        )
    }

    private static func uninstallClaudeCompatible(settingsURL: URL) throws {
        try uninstallGroupedJSONHooks(
            at: settingsURL,
            eventNames: ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "StopFailure", "SubagentStart", "SubagentStop"]
        )
    }

    private static func installCursor(command: String) throws {
        let url = homeURL.appendingPathComponent(".cursor/hooks.json")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var root = try loadJSONObject(at: url)
        root["version"] = 1
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events = ["beforeSubmitPrompt", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "afterFileEdit", "stop"]

        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries = entries.filter { !isManagedCommand($0["command"] as? String) }
            entries.append(["command": command])
            hooks[event] = entries
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private static func uninstallCursor() throws {
        let url = homeURL.appendingPathComponent(".cursor/hooks.json")
        guard fileManager.fileExists(atPath: url.path) else { return }

        var root = try loadJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ["beforeSubmitPrompt", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "afterFileEdit", "stop"] {
            let entries = hooks[event] as? [[String: Any]] ?? []
            let filtered = entries.filter { !isManagedCommand($0["command"] as? String) }
            hooks[event] = filtered.isEmpty ? nil : filtered
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSONObject(root, to: url)
    }

    private static func installGemini(command: String) throws {
        let url = homeURL.appendingPathComponent(".gemini/settings.json")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try installGroupedJSONHooks(
            at: url,
            eventSpecs: [
                ("SessionStart", "*"),
                ("SessionEnd", "*"),
                ("BeforeAgent", "*"),
                ("AfterAgent", "*"),
            ],
            command: command,
            includeName: true
        )
    }

    private static func uninstallGemini() throws {
        try uninstallGroupedJSONHooks(at: homeURL.appendingPathComponent(".gemini/settings.json"), eventNames: ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent"])
    }

    private static func installKimi(command: String) throws {
        let url = homeURL.appendingPathComponent(".kimi/config.toml")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var output = stripKimiManagedBlocks(from: original)
        if !output.isEmpty, !output.hasSuffix("\n") {
            output += "\n"
        }
        if !output.isEmpty {
            output += "\n"
        }

        for event in ["SessionStart", "UserPromptSubmit", "Stop", "PreToolUse", "PostToolUse"] {
            output += """
            # macafk: managed hook - do not edit
            [[hooks]]
            event = "\(event)"
            command = \(tomlStringLiteral(command))
            timeout = 45

            """
        }

        try writeText(output, to: url)
    }

    private static func uninstallKimi() throws {
        let url = homeURL.appendingPathComponent(".kimi/config.toml")
        guard let original = try? String(contentsOf: url, encoding: .utf8) else { return }
        try writeText(stripKimiManagedBlocks(from: original), to: url)
    }

    private static func installGroupedJSONHooks(
        at url: URL,
        eventSpecs: [(name: String, matcher: String?)],
        command: String,
        includeName: Bool
    ) throws {
        var root = try loadJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for spec in eventSpecs {
            let existing = hooks[spec.name] as? [Any] ?? []
            let cleaned = existing.compactMap { item -> [String: Any]? in
                guard var group = item as? [String: Any] else { return nil }
                let groupHooks = group["hooks"] as? [Any] ?? []
                let filteredHooks = groupHooks.compactMap { hook -> [String: Any]? in
                    guard let hook = hook as? [String: Any] else { return nil }
                    return isManagedCommand(hook["command"] as? String) ? nil : hook
                }
                guard !filteredHooks.isEmpty else { return nil }
                group["hooks"] = filteredHooks
                return group
            }

            var hook: [String: Any] = [
                "type": "command",
                "command": command,
            ]
            if includeName {
                hook["name"] = marker
            }

            var group: [String: Any] = ["hooks": [hook]]
            if let matcher = spec.matcher {
                group["matcher"] = matcher
            }
            hooks[spec.name] = cleaned + [group]
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private static func uninstallGroupedJSONHooks(at url: URL, eventNames: [String]) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        var root = try loadJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in eventNames {
            let existing = hooks[eventName] as? [Any] ?? []
            let cleaned = existing.compactMap { item -> [String: Any]? in
                guard var group = item as? [String: Any] else { return nil }
                let groupHooks = group["hooks"] as? [Any] ?? []
                let filteredHooks = groupHooks.compactMap { hook -> [String: Any]? in
                    guard let hook = hook as? [String: Any] else { return nil }
                    return isManagedCommand(hook["command"] as? String) ? nil : hook
                }
                guard !filteredHooks.isEmpty else { return nil }
                group["hooks"] = filteredHooks
                return group
            }
            hooks[eventName] = cleaned.isEmpty ? nil : cleaned
        }

        root["hooks"] = hooks.isEmpty ? nil : hooks
        try writeJSONObject(root, to: url)
    }

    private static func enableCodexHooksFeature(at url: URL) throws {
        let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = enableTomlFeature("hooks", in: original)
        try writeText(updated, to: url)
    }

    private static func enableTomlFeature(_ key: String, in contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")
        var inFeatures = false
        var sawFeatures = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                inFeatures = true
                sawFeatures = true
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inFeatures = false
            }
            if inFeatures && (trimmed.hasPrefix("\(key)") || trimmed.hasPrefix("codex_hooks")) {
                lines[index] = "\(key) = true"
                return lines.joined(separator: "\n")
            }
        }

        if sawFeatures, let index = lines.firstIndex(of: "[features]") {
            lines.insert("\(key) = true", at: index + 1)
            return lines.joined(separator: "\n")
        }

        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("\(key) = true")
        return lines.joined(separator: "\n")
    }

    private static func loadJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backupFileIfPresent(at: url)
        if object.isEmpty {
            try? fileManager.removeItem(at: url)
            return
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backupFileIfPresent(at: url)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? fileManager.removeItem(at: url)
            return
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func backupFileIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("macafk-backup.\(stamp)")
        try? fileManager.removeItem(at: backupURL)
        try fileManager.copyItem(at: url, to: backupURL)
    }

    private static func hookCommand(_ helperPath: String, source: String) -> String {
        "\(shellQuote(helperPath)) --source \(source)"
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isManagedCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        return command.contains(managedCommandNeedle)
    }

    private static func stripKimiManagedBlocks(from contents: String) -> String {
        let lines = contents.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "# macafk: managed hook - do not edit" {
                index += 1
                while index < lines.count {
                    let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("[[hooks]]") {
                        index += 1
                        while index < lines.count {
                            let next = lines[index].trimmingCharacters(in: .whitespaces)
                            if next.hasPrefix("[") {
                                break
                            }
                            index += 1
                        }
                        break
                    }
                    if !trimmed.isEmpty {
                        break
                    }
                    index += 1
                }
                if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return output.joined(separator: "\n")
    }

    private static func tomlStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
