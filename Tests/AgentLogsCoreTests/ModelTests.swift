import Testing
import Foundation
@testable import AgentLogsCore

@Suite("Model Records")
struct ModelTests {

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore()
    }

    // MARK: - Session Tests

    @Test("Session can be inserted and fetched via SQLiteStore")
    func sessionInsertAndFetch() throws {
        let store = try makeStore()
        let sessionID = UUID()
        let session = Session(
            id: sessionID,
            appName: "TestApp",
            appVersion: "1.0",
            bundleID: "com.test.app",
            osName: "macOS",
            osVersion: "15.0.0",
            deviceModel: "MacBookPro"
        )
        try store.insertSession(session)

        let sessions = try store.fetchSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].id == sessionID)
        #expect(sessions[0].appName == "TestApp")
        #expect(sessions[0].appVersion == "1.0")
        #expect(sessions[0].bundleID == "com.test.app")
        #expect(sessions[0].osName == "macOS")
        #expect(sessions[0].osVersion == "15.0.0")
        #expect(sessions[0].deviceModel == "MacBookPro")
        #expect(sessions[0].isCrashed == false)
    }

    @Test("Session model can be created with all properties")
    func sessionModelProperties() {
        let id = UUID()
        let now = Date()
        let session = Session(
            id: id,
            appName: "MyApp",
            appVersion: "2.0",
            bundleID: "com.example",
            osName: "iOS",
            osVersion: "18.0",
            deviceModel: "iPhone16,1",
            startedAt: now,
            endedAt: nil,
            isCrashed: true
        )
        #expect(session.id == id)
        #expect(session.appName == "MyApp")
        #expect(session.appVersion == "2.0")
        #expect(session.bundleID == "com.example")
        #expect(session.osName == "iOS")
        #expect(session.osVersion == "18.0")
        #expect(session.deviceModel == "iPhone16,1")
        #expect(session.startedAt == now)
        #expect(session.endedAt == nil)
        #expect(session.isCrashed == true)
    }

    @Test("Session can be updated (end session, mark crashed)")
    func sessionUpdate() throws {
        let store = try makeStore()
        let sessionID = UUID()
        let session = Session(
            id: sessionID,
            appName: "TestApp",
            osName: "macOS",
            osVersion: "15.0",
            deviceModel: "Mac"
        )
        try store.insertSession(session)
        try store.markSessionCrashed(id: sessionID)

        let sessions = try store.fetchSessions()
        #expect(sessions[0].isCrashed == true)
        #expect(sessions[0].endedAt != nil)
    }

    // MARK: - LogEntry Tests

    @Test("LogEntry can be inserted and fetched")
    func logEntryInsertAndFetch() throws {
        let store = try makeStore()
        let sessionID = UUID()
        try store.insertSession(Session(
            id: sessionID, appName: "TestApp", osName: "macOS", osVersion: "15.0", deviceModel: "Mac"
        ))

        let entry = SQLiteStore.PendingLog(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            category: .manualLogs,
            level: .info,
            message: "Hello world",
            sourceFile: "Test.swift",
            sourceLine: 42
        )
        try store.insertLogEntries([entry])

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 1)
        #expect(logs[0].message == "Hello world")
        #expect(logs[0].category == .manualLogs)
        #expect(logs[0].level == .info)
        #expect(logs[0].sourceFile == "Test.swift")
        #expect(logs[0].sourceLine == 42)
    }

    @Test("Multiple log entries can be inserted for one session")
    func multipleLogEntries() throws {
        let store = try makeStore()
        let sessionID = UUID()
        try store.insertSession(Session(
            id: sessionID, appName: "TestApp", osName: "macOS", osVersion: "15.0", deviceModel: "Mac"
        ))

        let entries = (0..<3).map { i in
            SQLiteStore.PendingLog(
                sessionID: sessionID,
                timestamp: Date(timeIntervalSinceReferenceDate: Double(i * 100)),
                category: .manualLogs,
                level: .info,
                message: "Entry \(i)"
            )
        }
        try store.insertLogEntries(entries)

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 3)
    }

    // MARK: - HTTPEntry Tests

    @Test("HTTPEntry can be inserted and fetched")
    func httpEntryInsertAndFetch() throws {
        let store = try makeStore()
        let sessionID = UUID()
        try store.insertSession(Session(
            id: sessionID, appName: "TestApp", osName: "macOS", osVersion: "15.0", deviceModel: "Mac"
        ))

        let entry = SQLiteStore.PendingLog(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            category: .http,
            level: .info,
            message: "GET /data",
            http: SQLiteStore.PendingHTTP(
                method: "GET",
                url: "https://api.example.com/data",
                requestHeaders: "{\"Accept\": \"application/json\"}",
                statusCode: 200,
                responseHeaders: "{\"Content-Type\": \"application/json\"}",
                responseBody: "{\"ok\": true}",
                durationMs: 123.45
            )
        )
        let ids = try store.insertLogEntries([entry])

        let httpEntry = try store.fetchHTTPEntry(logEntryID: Int(ids[0]))
        #expect(httpEntry != nil)
        #expect(httpEntry?.method == "GET")
        #expect(httpEntry?.url == "https://api.example.com/data")
        #expect(httpEntry?.statusCode == 200)
        #expect(httpEntry?.durationMs == 123.45)
        #expect(httpEntry?.responseBody == "{\"ok\": true}")
    }

    // MARK: - LogLevel & LogCategory

    @Test("LogLevel rawValues match expected strings")
    func logLevelRawValues() {
        #expect(LogLevel.debug.rawValue == "debug")
        #expect(LogLevel.info.rawValue == "info")
        #expect(LogLevel.warning.rawValue == "warning")
        #expect(LogLevel.error.rawValue == "error")
        #expect(LogLevel.critical.rawValue == "critical")
    }

    @Test("LogCategory rawValues match expected strings")
    func logCategoryRawValues() {
        #expect(LogCategory.http.rawValue == "http")
        #expect(LogCategory.system.rawValue == "system")
        #expect(LogCategory.oslog.rawValue == "oslog")
        #expect(LogCategory.manualLogs.rawValue == "manualLogs")
        #expect(LogCategory(rawValue: "custom").rawValue == "custom")
    }
}
