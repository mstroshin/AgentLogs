import Foundation
import AgentLogsCore

enum JSONFormatter: Sendable {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func formatSessions(_ sessions: [Session]) -> String {
        encode(sessions)
    }

    static func formatLogs(_ entries: [LogEntry]) -> String {
        encode(entries)
    }

    static func formatHTTPEntry(_ entry: HTTPEntry) -> String {
        encode(entry)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = makeEncoder()
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
