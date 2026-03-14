import Foundation
import AgentLogsCore

enum HumanFormatter: Sendable {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Sessions

    static func formatSessions(_ sessions: [Session]) -> String {
        if sessions.isEmpty { return "No sessions found." }

        var lines: [String] = []
        for session in sessions {
            let status = session.isCrashed ? " [CRASHED]" : ""
            let ended = session.endedAt.map { dateTimeFormatter.string(from: $0) } ?? "running"
            let version = session.appVersion ?? "?"
            lines.append(
                "\(session.id.uuidString)  \(session.appName) v\(version)  " +
                "\(session.osName) \(session.osVersion)  \(session.deviceModel)  " +
                "\(dateTimeFormatter.string(from: session.startedAt)) -> \(ended)\(status)"
            )
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Log Entries

    static func formatLogs(_ entries: [LogEntry]) -> String {
        if entries.isEmpty { return "No log entries found." }
        return entries.map { formatLogEntry($0) }.joined(separator: "\n")
    }

    static func formatLogEntry(_ entry: LogEntry) -> String {
        let time = timeFormatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        let category = entry.category.rawValue.uppercased()
        var line = "[\(time)] \(level) [\(category)] \(entry.message)"

        if let metadata = entry.metadata, !metadata.isEmpty {
            line += "\n    metadata: \(metadata)"
        }
        if let file = entry.sourceFile {
            let lineNum = entry.sourceLine.map { ":\($0)" } ?? ""
            line += "\n    at \(file)\(lineNum)"
        }
        return line
    }

    // MARK: - HTTP Entry

    static func formatHTTPEntry(_ entry: HTTPEntry, logEntry: LogEntry?) -> String {
        var lines: [String] = []

        let status = entry.statusCode.map { "\($0)" } ?? "pending"
        let duration = entry.durationMs.map { String(format: "%.0fms", $0) } ?? "?"
        lines.append("\(entry.method) \(entry.url) -> \(status) (\(duration))")

        if let logEntry {
            lines.append("Timestamp: \(dateTimeFormatter.string(from: logEntry.timestamp))")
            lines.append("Level: \(logEntry.level.rawValue.uppercased())")
        }

        if let headers = entry.requestHeaders, !headers.isEmpty {
            lines.append("\n--- Request Headers ---")
            lines.append(headers)
        }

        if let body = entry.requestBody, !body.isEmpty {
            lines.append("\n--- Request Body ---")
            lines.append(body)
        }

        if let headers = entry.responseHeaders, !headers.isEmpty {
            lines.append("\n--- Response Headers ---")
            lines.append(headers)
        }

        if let body = entry.responseBody, !body.isEmpty {
            lines.append("\n--- Response Body ---")
            lines.append(body)
        }

        return lines.joined(separator: "\n")
    }
}
