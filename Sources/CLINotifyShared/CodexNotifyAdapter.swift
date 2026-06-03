import Foundation

public enum CodexNotifyAdapter {
    public static func event(from payload: String, tty: String?, cwd: String?) -> AgentEvent {
        let object = decodeObject(payload)
        let rawType = stringValue(for: ["type", "event", "kind", "name"], in: object)
        let type = mapEventType(rawType)
        let turnID = stringValue(for: ["turn-id", "turn_id", "turnId"], in: object)
        let title = stringValue(for: ["title", "message", "summary"], in: object)
        let payloadCWD = stringValue(for: ["cwd", "current_dir", "current-directory"], in: object)

        return AgentEvent(
            source: .codex,
            type: type,
            tty: tty,
            cwd: payloadCWD ?? cwd,
            session: turnID,
            title: title
        )
    }

    private static func decodeObject(_ payload: String) -> [String: Any] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func mapEventType(_ rawType: String?) -> EventType {
        guard let rawType = rawType?.lowercased() else { return .done }
        if rawType.contains("approval")
            || rawType.contains("attention")
            || rawType.contains("prompt")
            || rawType.contains("blocked")
            || rawType.contains("input") {
            return .attention
        }
        return .done
    }
}
