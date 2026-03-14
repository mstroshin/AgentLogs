import Foundation
import AgentLogsCore

enum ToonFormatter: Sendable {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Shortened names

    private static func shortLevel(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "DBG"
        case .info: return "INF"
        case .warning: return "WRN"
        case .error: return "ERR"
        case .critical: return "CRT"
        }
    }

    private static func shortCategory(_ category: LogCategory) -> String {
        switch category {
        case .http: return "http"
        case .system: return "sys"
        case .oslog: return "osl"
        case .custom: return "cst"
        }
    }

    private static func truncate(_ str: String, maxLength: Int = 120) -> String {
        if str.count <= maxLength { return str }
        return String(str.prefix(maxLength - 3)) + "..."
    }

    // MARK: - Sessions

    static func formatSessions(_ sessions: [Session]) -> String {
        if sessions.isEmpty { return "no sessions" }
        return sessions.map { session in
            let status = session.isCrashed ? "CRASH" : "ok"
            let ended = session.endedAt != nil ? "ended" : "running"
            return "\(session.id.uuidString)|\(session.appName)|\(session.osName) \(session.osVersion)|\(session.deviceModel)|\(ended)|\(status)"
        }.joined(separator: "\n")
    }

    // MARK: - Log Entries

    static func formatLogs(_ entries: [LogEntry]) -> String {
        if entries.isEmpty { return "no logs" }
        return entries.map { formatLogEntry($0) }.joined(separator: "\n")
    }

    static func formatLogEntry(_ entry: LogEntry) -> String {
        let time = timeFormatter.string(from: entry.timestamp)
        let level = shortLevel(entry.level)
        let category = shortCategory(entry.category)
        let message = truncate(entry.message)
        return "\(time)|\(level)|\(category)|\(message)"
    }

    // MARK: - HTTP Entry

    static func formatHTTPEntry(_ entry: HTTPEntry) -> String {
        let path: String
        if let urlComponents = URLComponents(string: entry.url) {
            path = urlComponents.path
        } else {
            path = entry.url
        }
        let status = entry.statusCode.map { "\($0)" } ?? "?"
        let duration = entry.durationMs.map { String(format: "%.0fms", $0) } ?? "?"
        return "\(entry.method) \(path)->\(status) \(duration)"
    }
}
