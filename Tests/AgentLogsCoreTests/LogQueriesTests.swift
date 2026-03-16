import Testing
import Foundation
@testable import AgentLogsCore

@Suite("SQLiteStore Queries")
struct SQLiteStoreQueriesTests {

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore()
    }

    private func insertSession(
        store: SQLiteStore,
        id: UUID = UUID(),
        isCrashed: Bool = false,
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) throws -> UUID {
        let session = Session(
            id: id,
            appName: "TestApp",
            appVersion: "1.0",
            bundleID: "com.test.app",
            osName: "macOS",
            osVersion: "15.0.0",
            deviceModel: "MacBookPro",
            startedAt: startedAt,
            isCrashed: isCrashed
        )
        try store.insertSession(session)
        return id
    }

    @discardableResult
    private func insertLogEntry(
        store: SQLiteStore,
        sessionID: UUID,
        category: LogCategory = .manualLogs,
        level: LogLevel = .info,
        message: String = "Test message",
        timestamp: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) throws -> Int64 {
        let entry = SQLiteStore.PendingLog(
            sessionID: sessionID,
            timestamp: timestamp,
            category: category,
            level: level,
            message: message,
            sourceFile: "Test.swift",
            sourceLine: 42
        )
        let ids = try store.insertLogEntries([entry])
        return ids[0]
    }

    // MARK: - fetchSessions

    @Test("fetchSessions returns all sessions ordered by startedAt DESC")
    func fetchSessionsAll() throws {
        let store = try makeStore()

        try insertSession(store: store, startedAt: Date(timeIntervalSinceReferenceDate: 1000))
        try insertSession(store: store, startedAt: Date(timeIntervalSinceReferenceDate: 2000))
        try insertSession(store: store, startedAt: Date(timeIntervalSinceReferenceDate: 3000))

        let sessions = try store.fetchSessions()
        #expect(sessions.count == 3)
        #expect(sessions[0].startedAt > sessions[1].startedAt)
        #expect(sessions[1].startedAt > sessions[2].startedAt)
    }

    @Test("fetchSessions with crashedOnly filter")
    func fetchSessionsCrashedOnly() throws {
        let store = try makeStore()

        try insertSession(store: store, isCrashed: false)
        try insertSession(store: store, isCrashed: true)
        try insertSession(store: store, isCrashed: false)

        let crashed = try store.fetchSessions(crashedOnly: true)
        #expect(crashed.count == 1)
        #expect(crashed[0].isCrashed == true)
    }

    @Test("fetchSessions respects limit and offset")
    func fetchSessionsLimitOffset() throws {
        let store = try makeStore()

        for i in 0..<5 {
            try insertSession(store: store, startedAt: Date(timeIntervalSinceReferenceDate: Double(i * 1000)))
        }

        let page = try store.fetchSessions(limit: 2, offset: 1)
        #expect(page.count == 2)
    }

    @Test("fetchSessions returns empty array when none exist")
    func fetchSessionsEmpty() throws {
        let store = try makeStore()
        let sessions = try store.fetchSessions()
        #expect(sessions.isEmpty)
    }

    // MARK: - fetchLogs

    @Test("fetchLogs returns entries for given session")
    func fetchLogsForSession() throws {
        let store = try makeStore()
        let sessionID = UUID()
        let otherSessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertSession(store: store, id: otherSessionID)
        try insertLogEntry(store: store, sessionID: sessionID, message: "Mine")
        try insertLogEntry(store: store, sessionID: otherSessionID, message: "Other")

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 1)
        #expect(logs[0].message == "Mine")
    }

    @Test("fetchLogs filters by category")
    func fetchLogsFilterCategory() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, category: .http, message: "HTTP request")
        try insertLogEntry(store: store, sessionID: sessionID, category: .manualLogs, message: "Manual log")
        try insertLogEntry(store: store, sessionID: sessionID, category: .system, message: "System log")

        let httpLogs = try store.fetchLogs(sessionID: sessionID, category: .http)
        #expect(httpLogs.count == 1)
        #expect(httpLogs[0].message == "HTTP request")
    }

    @Test("fetchLogs filters by level")
    func fetchLogsFilterLevel() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, level: .info, message: "Info")
        try insertLogEntry(store: store, sessionID: sessionID, level: .error, message: "Error")
        try insertLogEntry(store: store, sessionID: sessionID, level: .debug, message: "Debug")

        let errors = try store.fetchLogs(sessionID: sessionID, level: .error)
        #expect(errors.count == 1)
        #expect(errors[0].message == "Error")
    }

    @Test("fetchLogs filters by sinceTimestamp")
    func fetchLogsFilterTimestamp() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, message: "Old", timestamp: Date(timeIntervalSinceReferenceDate: 1000))
        try insertLogEntry(store: store, sessionID: sessionID, message: "New", timestamp: Date(timeIntervalSinceReferenceDate: 3000))

        let recent = try store.fetchLogs(
            sessionID: sessionID,
            sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
        )
        #expect(recent.count == 1)
        #expect(recent[0].message == "New")
    }

    @Test("fetchLogs respects limit")
    func fetchLogsLimit() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        for i in 0..<10 {
            try insertLogEntry(store: store, sessionID: sessionID, message: "Entry \(i)",
                              timestamp: Date(timeIntervalSinceReferenceDate: Double(i * 100)))
        }

        let logs = try store.fetchLogs(sessionID: sessionID, limit: 3)
        #expect(logs.count == 3)
    }

    @Test("fetchLogs with combined filters")
    func fetchLogsCombinedFilters() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, category: .http, level: .error,
                          message: "HTTP error old", timestamp: Date(timeIntervalSinceReferenceDate: 1000))
        try insertLogEntry(store: store, sessionID: sessionID, category: .http, level: .error,
                          message: "HTTP error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000))
        try insertLogEntry(store: store, sessionID: sessionID, category: .manualLogs, level: .error,
                          message: "Manual error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000))

        let results = try store.fetchLogs(
            sessionID: sessionID, category: .http, level: .error,
            sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
        )
        #expect(results.count == 1)
        #expect(results[0].message == "HTTP error new")
    }

    // MARK: - tailLogs

    @Test("tailLogs returns entries after a given ID")
    func tailLogsAfterID() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        let firstID = try insertLogEntry(store: store, sessionID: sessionID, message: "First")
        try insertLogEntry(store: store, sessionID: sessionID, message: "Second")
        try insertLogEntry(store: store, sessionID: sessionID, message: "Third")

        let tail = try store.tailLogs(sessionID: sessionID, afterID: Int(firstID))
        #expect(tail.count == 2)
        #expect(tail[0].message == "Second")
        #expect(tail[1].message == "Third")
    }

    @Test("tailLogs returns empty when no new entries")
    func tailLogsEmpty() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        let lastID = try insertLogEntry(store: store, sessionID: sessionID, message: "Only one")

        let tail = try store.tailLogs(sessionID: sessionID, afterID: Int(lastID))
        #expect(tail.isEmpty)
    }

    // MARK: - fetchHTTPEntry

    @Test("fetchHTTPEntry returns matching entry")
    func fetchHTTPEntryFound() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        let entry = SQLiteStore.PendingLog(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            category: .http,
            level: .info,
            message: "POST /data",
            http: SQLiteStore.PendingHTTP(
                method: "POST",
                url: "https://api.example.com/data",
                statusCode: 201,
                durationMs: 99.5
            )
        )
        let ids = try store.insertLogEntries([entry])

        let fetched = try store.fetchHTTPEntry(logEntryID: Int(ids[0]))
        #expect(fetched != nil)
        #expect(fetched?.method == "POST")
        #expect(fetched?.url == "https://api.example.com/data")
        #expect(fetched?.statusCode == 201)
    }

    @Test("fetchHTTPEntry returns nil when not found")
    func fetchHTTPEntryNotFound() throws {
        let store = try makeStore()
        let result = try store.fetchHTTPEntry(logEntryID: 9999)
        #expect(result == nil)
    }

    // MARK: - searchLogs

    @Test("searchLogs finds entries matching query")
    func searchLogsMatchingQuery() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, message: "User logged in successfully")
        try insertLogEntry(store: store, sessionID: sessionID, message: "Network error occurred")
        try insertLogEntry(store: store, sessionID: sessionID, message: "User logged out")

        let results = try store.searchLogs(query: "logged")
        #expect(results.count == 2)
    }

    @Test("searchLogs filters by sessionID")
    func searchLogsFilterSession() throws {
        let store = try makeStore()
        let sessionA = UUID()
        let sessionB = UUID()

        try insertSession(store: store, id: sessionA)
        try insertSession(store: store, id: sessionB)
        try insertLogEntry(store: store, sessionID: sessionA, message: "Error in A")
        try insertLogEntry(store: store, sessionID: sessionB, message: "Error in B")

        let results = try store.searchLogs(query: "Error", sessionID: sessionA)
        #expect(results.count == 1)
        #expect(results[0].message == "Error in A")
    }

    @Test("searchLogs filters by category and level")
    func searchLogsFilterCategoryLevel() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, category: .http, level: .error, message: "HTTP failure")
        try insertLogEntry(store: store, sessionID: sessionID, category: .manualLogs, level: .error, message: "Manual failure")
        try insertLogEntry(store: store, sessionID: sessionID, category: .http, level: .info, message: "HTTP success")

        let results = try store.searchLogs(query: "HTTP", category: .http, level: .error)
        #expect(results.count == 1)
        #expect(results[0].message == "HTTP failure")
    }

    @Test("searchLogs returns empty for non-matching query")
    func searchLogsNoMatch() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, message: "Hello world")

        let results = try store.searchLogs(query: "zzzznotfound")
        #expect(results.isEmpty)
    }

    @Test("searchLogs respects limit")
    func searchLogsLimit() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        for i in 0..<10 {
            try insertLogEntry(store: store, sessionID: sessionID, message: "Match item \(i)")
        }

        let results = try store.searchLogs(query: "Match", limit: 3)
        #expect(results.count == 3)
    }

    // MARK: - latestSessionID

    @Test("latestSessionID returns most recent session")
    func latestSessionIDReturnsNewest() throws {
        let store = try makeStore()
        let oldID = UUID()
        let newID = UUID()

        try insertSession(store: store, id: oldID, startedAt: Date(timeIntervalSinceReferenceDate: 1000))
        try insertSession(store: store, id: newID, startedAt: Date(timeIntervalSinceReferenceDate: 5000))

        let latest = try store.latestSessionID()
        #expect(latest == newID)
    }

    @Test("latestSessionID returns nil when no sessions")
    func latestSessionIDEmpty() throws {
        let store = try makeStore()
        let latest = try store.latestSessionID()
        #expect(latest == nil)
    }

    // MARK: - fetchErrors

    @Test("fetchErrors returns only error and critical entries")
    func fetchErrorsFiltersCorrectly() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, level: .debug, message: "Debug")
        try insertLogEntry(store: store, sessionID: sessionID, level: .info, message: "Info")
        try insertLogEntry(store: store, sessionID: sessionID, level: .warning, message: "Warning")
        try insertLogEntry(store: store, sessionID: sessionID, level: .error, message: "Error")
        try insertLogEntry(store: store, sessionID: sessionID, level: .critical, message: "Critical")

        let errors = try store.fetchErrors(sessionID: sessionID)
        #expect(errors.count == 2)
        let messages = Set(errors.map { $0.message })
        #expect(messages.contains("Error"))
        #expect(messages.contains("Critical"))
    }

    @Test("fetchErrors returns empty when no errors exist")
    func fetchErrorsEmpty() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        try insertLogEntry(store: store, sessionID: sessionID, level: .info, message: "All good")

        let errors = try store.fetchErrors(sessionID: sessionID)
        #expect(errors.isEmpty)
    }

    @Test("fetchErrors respects limit")
    func fetchErrorsLimit() throws {
        let store = try makeStore()
        let sessionID = UUID()

        try insertSession(store: store, id: sessionID)
        for i in 0..<10 {
            try insertLogEntry(store: store, sessionID: sessionID, level: .error, message: "Error \(i)")
        }

        let errors = try store.fetchErrors(sessionID: sessionID, limit: 3)
        #expect(errors.count == 3)
    }
}
