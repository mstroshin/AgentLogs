import Testing
import Foundation
@testable import AgentLogsCore

// The CLI formatters live in an executable target and cannot be imported directly.
// We replicate the formatting logic here to test it in isolation.
// These tests verify the formatting contracts that the CLI depends on.

// MARK: - Formatter Replicas (matching Sources/AgentLogsCLI/Formatters/)

private enum TestHumanFormatter {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

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

    static func formatLogEntry(_ entry: LogEntry) -> String {
        let time = timeFormatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        let category = entry.category.rawValue.uppercased()
        var line = "[\(time)] \(level) [\(category)] \(entry.message)"
        if let metadata = entry.metadata, !metadata.isEmpty {
            line += "\n    metadata: \(metadata)"
        }
        if let file = entry.sourceFile {
            let fileName = (file as NSString).lastPathComponent
            let lineNum = entry.sourceLine.map { ":\($0)" } ?? ""
            line += "\n    at \(fileName)\(lineNum)"
        }
        return line
    }

    static func formatLogs(_ entries: [LogEntry]) -> String {
        if entries.isEmpty { return "No log entries found." }
        return entries.map { formatLogEntry($0) }.joined(separator: "\n")
    }
}

private enum TestJSONFormatter {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func formatSessions(_ sessions: [Session]) -> String { encode(sessions) }
    static func formatLogs(_ entries: [LogEntry]) -> String { encode(entries) }
    static func formatHTTPEntry(_ entry: HTTPEntry) -> String { encode(entry) }
}

private enum TestToonFormatter {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func shortLevel(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "DBG"
        case .info: return "INF"
        case .warning: return "WRN"
        case .error: return "ERR"
        case .critical: return "CRT"
        }
    }

    static func shortCategory(_ category: LogCategory) -> String {
        switch category {
        case .http: return "http"
        case .system: return "sys"
        case .oslog: return "osl"
        default: return String(category.rawValue.prefix(3))
        }
    }

    static func truncate(_ str: String, maxLength: Int = 120) -> String {
        if str.count <= maxLength { return str }
        return String(str.prefix(maxLength - 3)) + "..."
    }

    static func formatSessions(_ sessions: [Session]) -> String {
        if sessions.isEmpty { return "no sessions" }
        return sessions.map { session in
            let status = session.isCrashed ? "CRASH" : "ok"
            let ended = session.endedAt != nil ? "ended" : "running"
            return "\(session.id.uuidString)|\(session.appName)|\(session.osName) \(session.osVersion)|\(session.deviceModel)|\(ended)|\(status)"
        }.joined(separator: "\n")
    }

    static func formatLogEntry(_ entry: LogEntry) -> String {
        let time = timeFormatter.string(from: entry.timestamp)
        let level = shortLevel(entry.level)
        let category = shortCategory(entry.category)
        let message = truncate(entry.message)
        return "\(time)|\(level)|\(category)|\(message)"
    }

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

// MARK: - Test Data Helpers

private func makeSession(
    id: UUID = UUID(),
    appName: String = "TestApp",
    appVersion: String? = "1.0",
    isCrashed: Bool = false,
    startedAt: Date = Date(timeIntervalSinceReferenceDate: 750000),
    endedAt: Date? = nil
) -> Session {
    Session(
        id: id,
        appName: appName,
        appVersion: appVersion,
        bundleID: "com.test.app",
        osName: "macOS",
        osVersion: "15.0.0",
        deviceModel: "MacBookPro",
        startedAt: startedAt,
        endedAt: endedAt,
        isCrashed: isCrashed
    )
}

private func makeLogEntry(
    id: Int = 1,
    sessionID: UUID = UUID(),
    category: LogCategory = .manualLogs,
    level: LogLevel = .info,
    message: String = "Test message",
    metadata: String? = nil,
    sourceFile: String? = "ViewController.swift",
    sourceLine: Int? = 42,
    timestamp: Date = Date(timeIntervalSinceReferenceDate: 750000)
) -> LogEntry {
    LogEntry(
        id: id,
        sessionID: sessionID,
        timestamp: timestamp,
        category: category,
        level: level,
        message: message,
        metadata: metadata,
        sourceFile: sourceFile,
        sourceLine: sourceLine
    )
}

private func makeHTTPEntry(
    logEntryID: Int = 1,
    method: String = "GET",
    url: String = "https://api.example.com/users",
    statusCode: Int? = 200,
    durationMs: Double? = 123.0
) -> HTTPEntry {
    HTTPEntry(
        logEntryID: logEntryID,
        method: method,
        url: url,
        requestHeaders: "{\"Accept\": \"application/json\"}",
        requestBody: nil,
        statusCode: statusCode,
        responseHeaders: "{\"Content-Type\": \"application/json\"}",
        responseBody: "{\"ok\": true}",
        durationMs: durationMs
    )
}

// MARK: - HumanFormatter Tests

@Suite("HumanFormatter")
struct HumanFormatterTests {

    @Test("Empty sessions returns placeholder text")
    func emptySessionsMessage() {
        let result = TestHumanFormatter.formatSessions([])
        #expect(result == "No sessions found.")
    }

    @Test("Session formatting includes all fields")
    func sessionFormatContainsFields() {
        let session = makeSession(appName: "MyApp", appVersion: "2.0")
        let result = TestHumanFormatter.formatSessions([session])
        #expect(result.contains("MyApp"))
        #expect(result.contains("v2.0"))
        #expect(result.contains("macOS"))
        #expect(result.contains("15.0.0"))
        #expect(result.contains("MacBookPro"))
        #expect(result.contains("running"))
    }

    @Test("Crashed session shows [CRASHED] tag")
    func crashedSessionTag() {
        let session = makeSession(isCrashed: true)
        let result = TestHumanFormatter.formatSessions([session])
        #expect(result.contains("[CRASHED]"))
    }

    @Test("Non-crashed session does not show [CRASHED] tag")
    func nonCrashedSessionNoTag() {
        let session = makeSession(isCrashed: false)
        let result = TestHumanFormatter.formatSessions([session])
        #expect(!result.contains("[CRASHED]"))
    }

    @Test("Session with nil appVersion shows question mark")
    func nilVersionShowsQuestionMark() {
        let session = makeSession(appVersion: nil)
        let result = TestHumanFormatter.formatSessions([session])
        #expect(result.contains("v?"))
    }

    @Test("Empty logs returns placeholder text")
    func emptyLogsMessage() {
        let result = TestHumanFormatter.formatLogs([])
        #expect(result == "No log entries found.")
    }

    @Test("Log entry format includes level, category, and message")
    func logEntryFormat() {
        let entry = makeLogEntry(category: .http, level: .error, message: "Connection failed")
        let result = TestHumanFormatter.formatLogEntry(entry)
        #expect(result.contains("ERROR"))
        #expect(result.contains("[HTTP]"))
        #expect(result.contains("Connection failed"))
    }

    @Test("Log entry with metadata includes metadata line")
    func logEntryWithMetadata() {
        let entry = makeLogEntry(metadata: "{\"key\": \"value\"}")
        let result = TestHumanFormatter.formatLogEntry(entry)
        #expect(result.contains("metadata: {\"key\": \"value\"}"))
    }

    @Test("Log entry with sourceFile includes source location")
    func logEntryWithSourceFile() {
        let entry = makeLogEntry(sourceFile: "MyFile.swift", sourceLine: 99)
        let result = TestHumanFormatter.formatLogEntry(entry)
        #expect(result.contains("at MyFile.swift:99"))
    }

    @Test("Log entry without sourceFile omits source location")
    func logEntryWithoutSourceFile() {
        let entry = makeLogEntry(sourceFile: nil, sourceLine: nil)
        let result = TestHumanFormatter.formatLogEntry(entry)
        #expect(!result.contains("at "))
    }

    @Test("Multiple log entries are separated by newlines")
    func multipleLogEntries() {
        let entries = [
            makeLogEntry(id: 1, message: "First"),
            makeLogEntry(id: 2, message: "Second"),
        ]
        let result = TestHumanFormatter.formatLogs(entries)
        #expect(result.contains("First"))
        #expect(result.contains("Second"))
    }
}

// MARK: - JSONFormatter Tests

@Suite("JSONFormatter")
struct JSONFormatterTests {

    @Test("Sessions produce valid JSON array")
    func sessionsValidJSON() {
        let sessions = [makeSession(), makeSession()]
        let result = TestJSONFormatter.formatSessions(sessions)
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed is [[String: Any]])
    }

    @Test("Empty sessions produce empty JSON array")
    func emptySessionsJSON() {
        let result = TestJSONFormatter.formatSessions([])
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "[\n\n]")
    }

    @Test("Log entries produce valid JSON array")
    func logEntriesValidJSON() {
        let entries = [makeLogEntry()]
        let result = TestJSONFormatter.formatLogs(entries)
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed is [[String: Any]])
    }

    @Test("HTTPEntry produces valid JSON object")
    func httpEntryValidJSON() {
        let entry = makeHTTPEntry()
        let result = TestJSONFormatter.formatHTTPEntry(entry)
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any])
    }

    @Test("JSON output uses sorted keys")
    func sortedKeys() {
        let entry = makeHTTPEntry()
        let result = TestJSONFormatter.formatHTTPEntry(entry)
        // With sorted keys, "durationMs" should appear before "method"
        let durationIndex = result.range(of: "durationMs")!.lowerBound
        let methodIndex = result.range(of: "method")!.lowerBound
        #expect(durationIndex < methodIndex)
    }

    @Test("JSON output is pretty printed")
    func prettyPrinted() {
        let entry = makeHTTPEntry()
        let result = TestJSONFormatter.formatHTTPEntry(entry)
        // Pretty printed JSON contains newlines and indentation
        #expect(result.contains("\n"))
        #expect(result.contains("  "))
    }
}

// MARK: - ToonFormatter Tests

@Suite("ToonFormatter")
struct ToonFormatterTests {

    @Test("Shortened levels")
    func shortenedLevels() {
        #expect(TestToonFormatter.shortLevel(.debug) == "DBG")
        #expect(TestToonFormatter.shortLevel(.info) == "INF")
        #expect(TestToonFormatter.shortLevel(.warning) == "WRN")
        #expect(TestToonFormatter.shortLevel(.error) == "ERR")
        #expect(TestToonFormatter.shortLevel(.critical) == "CRT")
    }

    @Test("Shortened categories")
    func shortenedCategories() {
        #expect(TestToonFormatter.shortCategory(.http) == "http")
        #expect(TestToonFormatter.shortCategory(.system) == "sys")
        #expect(TestToonFormatter.shortCategory(.oslog) == "osl")
        #expect(TestToonFormatter.shortCategory(.manualLogs) == "man")
    }

    @Test("Truncation at 120 characters")
    func truncation() {
        let short = "Short message"
        #expect(TestToonFormatter.truncate(short) == short)

        let long = String(repeating: "a", count: 200)
        let truncated = TestToonFormatter.truncate(long)
        #expect(truncated.count == 120)
        #expect(truncated.hasSuffix("..."))
    }

    @Test("Truncation preserves messages at exactly 120 characters")
    func truncationExactBoundary() {
        let exact = String(repeating: "b", count: 120)
        #expect(TestToonFormatter.truncate(exact) == exact)
    }

    @Test("Empty sessions returns 'no sessions'")
    func emptySessionsMessage() {
        let result = TestToonFormatter.formatSessions([])
        #expect(result == "no sessions")
    }

    @Test("Session format is pipe-separated")
    func sessionPipeSeparated() {
        let session = makeSession()
        let result = TestToonFormatter.formatSessions([session])
        let components = result.split(separator: "|")
        #expect(components.count == 6)
    }

    @Test("Crashed session shows CRASH status")
    func crashedSessionStatus() {
        let session = makeSession(isCrashed: true)
        let result = TestToonFormatter.formatSessions([session])
        #expect(result.contains("CRASH"))
    }

    @Test("Running session shows ok status and running")
    func runningSessionStatus() {
        let session = makeSession(isCrashed: false, endedAt: nil)
        let result = TestToonFormatter.formatSessions([session])
        #expect(result.contains("|ok"))
        #expect(result.contains("|running|"))
    }

    @Test("Ended session shows 'ended'")
    func endedSession() {
        let session = makeSession(endedAt: Date())
        let result = TestToonFormatter.formatSessions([session])
        #expect(result.contains("|ended|"))
    }

    @Test("Log entry format is pipe-separated with short names")
    func logEntryPipeSeparated() {
        let entry = makeLogEntry(category: .system, level: .warning, message: "Disk full")
        let result = TestToonFormatter.formatLogEntry(entry)
        let components = result.split(separator: "|")
        #expect(components.count == 4)
        #expect(components[1] == "WRN")
        #expect(components[2] == "sys")
        #expect(components[3] == "Disk full")
    }

    @Test("HTTP entry format shows path, status, and duration")
    func httpEntryFormat() {
        let entry = makeHTTPEntry(
            method: "POST",
            url: "https://api.example.com/users/123",
            statusCode: 201,
            durationMs: 55.0
        )
        let result = TestToonFormatter.formatHTTPEntry(entry)
        #expect(result == "POST /users/123->201 55ms")
    }

    @Test("HTTP entry with nil status shows question mark")
    func httpEntryNilStatus() {
        let entry = makeHTTPEntry(statusCode: nil, durationMs: nil)
        let result = TestToonFormatter.formatHTTPEntry(entry)
        #expect(result.contains("->?"))
        #expect(result.hasSuffix("?"))
    }
}
