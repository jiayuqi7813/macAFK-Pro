import Foundation

enum AgentHookLifecycle: String {
    case started
    case activity
    case completed
    case ignored
}

struct AgentHookEvent: Identifiable, Equatable {
    let id: String
    let source: String
    let eventName: String
    let lifecycle: AgentHookLifecycle
    let sessionID: String
    let cwd: String?
    let receivedAt: Date
}

extension AgentHookEvent {
    var softwareDisplayName: String {
        switch source {
        case "codex":
            return "Codex"
        case "claude":
            return "Claude Code"
        case "qoder":
            return "Qoder"
        case "qwen":
            return "Qwen Code"
        case "factory":
            return "Factory"
        case "codebuddy":
            return "CodeBuddy"
        case "cursor":
            return "Cursor"
        case "gemini":
            return "Gemini CLI"
        case "kimi":
            return "Kimi CLI"
        default:
            return source.isEmpty ? "AI Agent" : source.capitalized
        }
    }

    var iconAssetName: String {
        switch source {
        case "codex":
            return "agent-icon-codex"
        case "claude":
            return "agent-icon-claude"
        case "cursor":
            return "agent-icon-cursor"
        case "gemini":
            return "agent-icon-gemini"
        case "kimi":
            return "agent-icon-kimi"
        case "qwen":
            return "agent-icon-qwen"
        case "qoder":
            return "agent-icon-qoder"
        case "codebuddy":
            return "agent-icon-codebuddy"
        case "factory":
            return "agent-icon-lobehub"
        default:
            return "agent-icon-lobehub"
        }
    }

    var taskDisplayName: String {
        if let cwd,
           let lastPathComponent = URL(fileURLWithPath: cwd).lastPathComponent.nilIfEmpty {
            return lastPathComponent
        }

        return shortSessionID
    }

    var shortSessionID: String {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return String(trimmed.prefix(12))
    }

    var sessionDeduplicationKey: String {
        let normalizedSession = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCWD = cwd?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
        return "\(normalizedSession)|\(normalizedCWD)"
    }

    var sourcePriority: Int {
        switch source {
        case "cursor":
            return 100
        case "codex":
            return 95
        case "claude":
            return 90
        case "qoder", "qwen", "factory", "codebuddy":
            return 85
        case "gemini", "kimi":
            return 80
        default:
            return 0
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct AgentHookEnvelope: Decodable {
    let source: String
    let timestamp: String?
    let payloadBase64: String
}

enum AgentHookEventParser {
    static func parseEnvelope(data: Data, fallbackID: String) -> AgentHookEvent? {
        guard let envelope = try? JSONDecoder().decode(AgentHookEnvelope.self, from: data),
              let payloadData = Data(base64Encoded: envelope.payloadBase64),
              let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] else {
            return nil
        }

        let source = normalizedSource(envelope.source)
        let eventName = stringValue(payload["hook_event_name"])
            ?? stringValue(payload["event"])
            ?? stringValue(payload["hookEventName"])
            ?? stringValue(payload["type"])
            ?? "unknown"
        let lifecycle = lifecycleForEvent(named: eventName)

        guard lifecycle != .ignored else {
            return nil
        }

        let sessionID = sessionIdentifier(from: payload, source: source, fallbackID: fallbackID)
        let receivedAt = date(from: envelope.timestamp) ?? .now
        let id = "\(source):\(sessionID)"

        return AgentHookEvent(
            id: id,
            source: source,
            eventName: eventName,
            lifecycle: lifecycle,
            sessionID: sessionID,
            cwd: stringValue(payload["cwd"]),
            receivedAt: receivedAt
        )
    }

    private static func lifecycleForEvent(named eventName: String) -> AgentHookLifecycle {
        switch eventName.lowercased() {
        case "sessionstart",
             "userpromptsubmit",
             "pretooluse",
             "subagentstart",
             "beforeagent",
             "beforesubmitprompt",
             "beforeshellexecution",
             "beforemcpexecution",
             "beforereadfile":
            return .started

        case "posttooluse",
             "afterfileedit",
             "notification":
            return .activity

        case "stop",
             "sessionend",
             "stopfailure",
             "subagentstop",
             "afteragent":
            return .completed

        default:
            return .ignored
        }
    }

    private static func sessionIdentifier(from payload: [String: Any], source: String, fallbackID: String) -> String {
        let baseID = stringValue(payload["session_id"])
            ?? stringValue(payload["conversation_id"])
            ?? stringValue(payload["generation_id"])
            ?? stringValue(payload["thread_id"])
            ?? stringValue(payload["turn_id"])
            ?? stringValue(payload["cwd"])
            ?? fallbackID

        if let agentID = stringValue(payload["agent_id"]) {
            return "\(baseID):\(agentID)"
        }

        return baseID
    }

    private static func normalizedSource(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty {
            return value
        }
        if let value = value as? CustomStringConvertible {
            let string = value.description
            return string.isEmpty ? nil : string
        }
        return nil
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
