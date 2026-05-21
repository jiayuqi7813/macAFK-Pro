import Testing
import AppKit
@testable import MacAfk_Pro

struct ShortcutConfigTests {

    @Test func displayStringIncludesModifiersAndKey() {
        let config = ShortcutConfig(
            action: .toggleJiggle,
            keyCode: 1,
            modifiers: [.command, .control],
            displayName: "Toggle"
        )

        #expect(config.displayString.contains("⌘"))
        #expect(config.displayString.contains("⌃"))
        #expect(config.displayString.contains("S"))
    }

    @Test func keyCodeToCharMapsKnownKeys() {
        #expect(ShortcutConfig.keyCodeToChar(1) == "S")
        #expect(ShortcutConfig.keyCodeToChar(11) == "B")
        #expect(ShortcutConfig.keyCodeToChar(126) == "↑")
    }

    @Test func configsWithSameBindingAreEqual() {
        let left = ShortcutConfig(action: .toggleJiggle, keyCode: 1, modifiers: [.command, .control], displayName: "Toggle")
        let right = ShortcutConfig(action: .toggleJiggle, keyCode: 1, modifiers: [.command, .control], displayName: "Toggle")
        #expect(left == right)
        #expect(left.keyCode == right.keyCode)
        #expect(left.modifierFlags == right.modifierFlags)
    }
}

struct ShortcutManagerTests {

    @Test func detectsShortcutConflict() {
        let manager = ShortcutManager()
        manager.resetToDefaults()

        let conflict = manager.findConflict(
            for: .toggleBrightness,
            keyCode: 1,
            modifiers: [.command, .control]
        )

        #expect(conflict == .toggleJiggle)
    }

    @Test func updateShortcutReturnsConflictWithoutSaving() {
        let manager = ShortcutManager()
        manager.resetToDefaults()
        let original = manager.shortcuts[.toggleBrightness]

        let conflict = manager.updateShortcut(
            for: .toggleBrightness,
            keyCode: 1,
            modifiers: [.command, .control]
        )

        #expect(conflict == .toggleJiggle)
        #expect(manager.shortcuts[.toggleBrightness] == original)
    }

    @Test func updateShortcutSavesWhenNoConflict() {
        let manager = ShortcutManager()
        manager.resetToDefaults()

        let conflict = manager.updateShortcut(
            for: .toggleBrightness,
            keyCode: 2,
            modifiers: [.command, .option]
        )

        #expect(conflict == nil)
        #expect(manager.shortcuts[.toggleBrightness]?.keyCode == 2)
        #expect(manager.shortcuts[.toggleBrightness]?.modifierFlags.contains(.option) == true)
    }

    @Test func resetToDefaultsRestoresDefaultBindings() {
        let manager = ShortcutManager()
        _ = manager.updateShortcut(for: .toggleJiggle, keyCode: 2, modifiers: [.option])

        manager.resetToDefaults()

        #expect(manager.shortcuts[.toggleJiggle]?.keyCode == 1)
        #expect(manager.shortcuts[.toggleJiggle]?.modifierFlags.contains(.command) == true)
    }
}

struct LaunchAtLoginHelperTests {

    @Test func isLaunchAtLoginEnabledReturnsBoolWithoutCrashing() {
        _ = LaunchAtLoginHelper.isLaunchAtLoginEnabled()
    }

    @Test func setLaunchAtLoginReturnsBool() {
        let current = LaunchAtLoginHelper.isLaunchAtLoginEnabled()
        let result = LaunchAtLoginHelper.setLaunchAtLogin(enabled: current)
        #expect(result == true)
        #expect(LaunchAtLoginHelper.isLaunchAtLoginEnabled() == current)
    }
}

struct UpdateManagerTests {

    @Test func newerVersionComparison() {
        let manager = UpdateManager.shared

        #expect(manager.isNewerVersionForTesting("1.1.0", than: "1.0.4") == true)
        #expect(manager.isNewerVersionForTesting("1.0.4", than: "1.0.4") == false)
        #expect(manager.isNewerVersionForTesting("v2.0.0", than: "1.9.9") == true)
        #expect(manager.isNewerVersionForTesting("1.0.3", than: "1.0.4") == false)
    }
}

struct AgentHookEventParserTests {

    @Test func parsesCodexStopAsCompleted() throws {
        let event = try parse(
            source: "codex",
            payload: [
                "hook_event_name": "Stop",
                "session_id": "codex-session",
                "cwd": "/tmp/project",
            ]
        )

        #expect(event.source == "codex")
        #expect(event.lifecycle == .completed)
        #expect(event.sessionID == "codex-session")
        #expect(event.cwd == "/tmp/project")
    }

    @Test func parsesClaudePromptAsStarted() throws {
        let event = try parse(
            source: "claude",
            payload: [
                "hook_event_name": "UserPromptSubmit",
                "session_id": "claude-session",
            ]
        )

        #expect(event.lifecycle == .started)
        #expect(event.id == "claude:claude-session")
    }

    @Test func parsesCursorStopConversationID() throws {
        let event = try parse(
            source: "cursor",
            payload: [
                "hook_event_name": "stop",
                "conversation_id": "cursor-conversation",
            ]
        )

        #expect(event.lifecycle == .completed)
        #expect(event.sessionID == "cursor-conversation")
    }

    private func parse(source: String, payload: [String: Any]) throws -> AgentHookEvent {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let envelope: [String: Any] = [
            "source": source,
            "timestamp": "2026-05-21T00:00:00Z",
            "payloadBase64": payloadData.base64EncodedString(),
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let event = AgentHookEventParser.parseEnvelope(data: envelopeData, fallbackID: "fallback")
        return try #require(event)
    }
}

extension UpdateManager {
    fileprivate func isNewerVersionForTesting(_ newVersion: String, than currentVersion: String) -> Bool {
        let new = newVersion.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(new.count, current.count) {
            let newPart = i < new.count ? new[i] : 0
            let currentPart = i < current.count ? current[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }
}
