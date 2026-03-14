import Testing
import Foundation
import GRDB
@testable import AgentLogsCore

@Suite("LogQueries")
struct LogQueriesTests {

    private func makeDatabase() throws -> DatabaseQueue {
        try DatabaseSetup.openInMemoryDatabase()
    }

    /// Insert a session using raw SQL with uuidString to match the production query patterns.
    private func insertSessionSQL(
        in db: Database,
        id: UUID = UUID(),
        isCrashed: Bool = false,
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO session (id, appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """,
            arguments: [
                id.uuidString,
                "TestApp",
                "1.0",
                "com.test.app",
                "macOS",
                "15.0.0",
                "MacBookPro",
                startedAt.timeIntervalSinceReferenceDate,
                isCrashed,
            ]
        )
    }

    private func insertLogEntry(
        in db: Database,
        sessionID: UUID,
        category: LogCategory = .custom,
        level: LogLevel = .info,
        message: String = "Test message",
        timestamp: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) throws -> Int {
        try db.execute(
            sql: """
                INSERT INTO logEntry (sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine)
                VALUES (?, ?, ?, ?, ?, NULL, 'Test.swift', 42)
                """,
            arguments: [
                sessionID.uuidString,
                timestamp.timeIntervalSinceReferenceDate,
                category.rawValue,
                level.rawValue,
                message,
            ]
        )
        return Int(db.lastInsertedRowID)
    }

    // MARK: - fetchSessions

    @Test("fetchSessions returns all sessions ordered by startedAt DESC")
    func fetchSessionsAll() throws {
        let db = try makeDatabase()

        try db.write { database in
            try insertSessionSQL(in: database, startedAt: Date(timeIntervalSinceReferenceDate: 1000))
            try insertSessionSQL(in: database, startedAt: Date(timeIntervalSinceReferenceDate: 2000))
            try insertSessionSQL(in: database, startedAt: Date(timeIntervalSinceReferenceDate: 3000))
        }

        let sessions = try db.read { database in
            try LogQueries.fetchSessions(db: database)
        }

        #expect(sessions.count == 3)
        #expect(sessions[0].startedAt > sessions[1].startedAt)
        #expect(sessions[1].startedAt > sessions[2].startedAt)
    }

    @Test("fetchSessions with crashedOnly filter")
    func fetchSessionsCrashedOnly() throws {
        let db = try makeDatabase()

        try db.write { database in
            try insertSessionSQL(in: database, isCrashed: false)
            try insertSessionSQL(in: database, isCrashed: true)
            try insertSessionSQL(in: database, isCrashed: false)
        }

        let crashed = try db.read { database in
            try LogQueries.fetchSessions(db: database, crashedOnly: true)
        }

        #expect(crashed.count == 1)
        #expect(crashed[0].isCrashed == true)
    }

    @Test("fetchSessions respects limit and offset")
    func fetchSessionsLimitOffset() throws {
        let db = try makeDatabase()

        try db.write { database in
            for i in 0..<5 {
                try insertSessionSQL(
                    in: database,
                    startedAt: Date(timeIntervalSinceReferenceDate: Double(i * 1000))
                )
            }
        }

        let page = try db.read { database in
            try LogQueries.fetchSessions(db: database, limit: 2, offset: 1)
        }

        #expect(page.count == 2)
    }

    @Test("fetchSessions returns empty array when none exist")
    func fetchSessionsEmpty() throws {
        let db = try makeDatabase()

        let sessions = try db.read { database in
            try LogQueries.fetchSessions(db: database)
        }

        #expect(sessions.isEmpty)
    }

    // MARK: - fetchLogs

    @Test("fetchLogs returns entries for given session")
    func fetchLogsForSession() throws {
        let db = try makeDatabase()
        let sessionID = UUID()
        let otherSessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            try insertSessionSQL(in: database, id: otherSessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Mine")
            _ = try insertLogEntry(in: database, sessionID: otherSessionID, message: "Other")
        }

        let logs = try db.read { database in
            try LogQueries.fetchLogs(db: database, sessionID: sessionID)
        }

        #expect(logs.count == 1)
        #expect(logs[0].message == "Mine")
    }

    @Test("fetchLogs filters by category")
    func fetchLogsFilterCategory() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, category: .http, message: "HTTP request")
            _ = try insertLogEntry(in: database, sessionID: sessionID, category: .custom, message: "Custom log")
            _ = try insertLogEntry(in: database, sessionID: sessionID, category: .system, message: "System log")
        }

        let httpLogs = try db.read { database in
            try LogQueries.fetchLogs(db: database, sessionID: sessionID, category: .http)
        }

        #expect(httpLogs.count == 1)
        #expect(httpLogs[0].message == "HTTP request")
    }

    @Test("fetchLogs filters by level")
    func fetchLogsFilterLevel() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .info, message: "Info")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .error, message: "Error")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .debug, message: "Debug")
        }

        let errors = try db.read { database in
            try LogQueries.fetchLogs(db: database, sessionID: sessionID, level: .error)
        }

        #expect(errors.count == 1)
        #expect(errors[0].message == "Error")
    }

    @Test("fetchLogs filters by sinceTimestamp")
    func fetchLogsFilterTimestamp() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, message: "Old",
                timestamp: Date(timeIntervalSinceReferenceDate: 1000)
            )
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, message: "New",
                timestamp: Date(timeIntervalSinceReferenceDate: 3000)
            )
        }

        let recent = try db.read { database in
            try LogQueries.fetchLogs(
                db: database,
                sessionID: sessionID,
                sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
            )
        }

        #expect(recent.count == 1)
        #expect(recent[0].message == "New")
    }

    @Test("fetchLogs respects limit")
    func fetchLogsLimit() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            for i in 0..<10 {
                _ = try insertLogEntry(
                    in: database, sessionID: sessionID, message: "Entry \(i)",
                    timestamp: Date(timeIntervalSinceReferenceDate: Double(i * 100))
                )
            }
        }

        let logs = try db.read { database in
            try LogQueries.fetchLogs(db: database, sessionID: sessionID, limit: 3)
        }

        #expect(logs.count == 3)
    }

    @Test("fetchLogs with combined filters")
    func fetchLogsCombinedFilters() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .http, level: .error,
                message: "HTTP error old", timestamp: Date(timeIntervalSinceReferenceDate: 1000)
            )
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .http, level: .error,
                message: "HTTP error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000)
            )
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .custom, level: .error,
                message: "Custom error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000)
            )
        }

        let results = try db.read { database in
            try LogQueries.fetchLogs(
                db: database,
                sessionID: sessionID,
                category: .http,
                level: .error,
                sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
            )
        }

        #expect(results.count == 1)
        #expect(results[0].message == "HTTP error new")
    }

    // MARK: - tailLogs

    @Test("tailLogs returns entries after a given ID")
    func tailLogsAfterID() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        var firstID: Int = 0
        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            firstID = try insertLogEntry(in: database, sessionID: sessionID, message: "First")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Second")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Third")
        }

        let tail = try db.read { database in
            try LogQueries.tailLogs(db: database, sessionID: sessionID, afterID: firstID)
        }

        #expect(tail.count == 2)
        #expect(tail[0].message == "Second")
        #expect(tail[1].message == "Third")
    }

    @Test("tailLogs returns empty when no new entries")
    func tailLogsEmpty() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        var lastID: Int = 0
        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            lastID = try insertLogEntry(in: database, sessionID: sessionID, message: "Only one")
        }

        let tail = try db.read { database in
            try LogQueries.tailLogs(db: database, sessionID: sessionID, afterID: lastID)
        }

        #expect(tail.isEmpty)
    }

    // MARK: - fetchHTTPEntry

    @Test("fetchHTTPEntry returns matching entry")
    func fetchHTTPEntryFound() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        let logEntryID = try db.write { database -> Int in
            try insertSessionSQL(in: database, id: sessionID)
            let entryID = try insertLogEntry(in: database, sessionID: sessionID, category: .http)
            try database.execute(
                sql: """
                    INSERT INTO httpEntry (logEntryID, method, url, requestHeaders, requestBody, statusCode, responseHeaders, responseBody, durationMs)
                    VALUES (?, ?, ?, NULL, NULL, ?, NULL, NULL, ?)
                    """,
                arguments: [entryID, "POST", "https://api.example.com/data", 201, 99.5]
            )
            return entryID
        }

        let fetched = try db.read { database in
            try LogQueries.fetchHTTPEntry(db: database, logEntryID: logEntryID)
        }

        #expect(fetched != nil)
        #expect(fetched?.method == "POST")
        #expect(fetched?.url == "https://api.example.com/data")
        #expect(fetched?.statusCode == 201)
    }

    @Test("fetchHTTPEntry returns nil when not found")
    func fetchHTTPEntryNotFound() throws {
        let db = try makeDatabase()
        let result = try db.read { database in
            try LogQueries.fetchHTTPEntry(db: database, logEntryID: 9999)
        }
        #expect(result == nil)
    }

    // MARK: - searchLogs

    @Test("searchLogs finds entries matching query")
    func searchLogsMatchingQuery() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "User logged in successfully")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Network error occurred")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "User logged out")
        }

        let results = try db.read { database in
            try LogQueries.searchLogs(db: database, query: "logged")
        }

        #expect(results.count == 2)
    }

    @Test("searchLogs filters by sessionID")
    func searchLogsFilterSession() throws {
        let db = try makeDatabase()
        let sessionA = UUID()
        let sessionB = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionA)
            try insertSessionSQL(in: database, id: sessionB)
            _ = try insertLogEntry(in: database, sessionID: sessionA, message: "Error in A")
            _ = try insertLogEntry(in: database, sessionID: sessionB, message: "Error in B")
        }

        let results = try db.read { database in
            try LogQueries.searchLogs(db: database, query: "Error", sessionID: sessionA)
        }

        #expect(results.count == 1)
        #expect(results[0].message == "Error in A")
    }

    @Test("searchLogs filters by category and level")
    func searchLogsFilterCategoryLevel() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .http, level: .error,
                message: "HTTP failure"
            )
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .custom, level: .error,
                message: "Custom failure"
            )
            _ = try insertLogEntry(
                in: database, sessionID: sessionID, category: .http, level: .info,
                message: "HTTP success"
            )
        }

        let results = try db.read { database in
            try LogQueries.searchLogs(
                db: database,
                query: "HTTP",
                category: .http,
                level: .error
            )
        }

        #expect(results.count == 1)
        #expect(results[0].message == "HTTP failure")
    }

    @Test("searchLogs returns empty for non-matching query")
    func searchLogsNoMatch() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Hello world")
        }

        let results = try db.read { database in
            try LogQueries.searchLogs(db: database, query: "zzzznotfound")
        }

        #expect(results.isEmpty)
    }

    @Test("searchLogs respects limit")
    func searchLogsLimit() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            for i in 0..<10 {
                _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Match item \(i)")
            }
        }

        let results = try db.read { database in
            try LogQueries.searchLogs(db: database, query: "Match", limit: 3)
        }

        #expect(results.count == 3)
    }

    // MARK: - latestSessionID

    @Test("latestSessionID returns most recent session")
    func latestSessionIDReturnsNewest() throws {
        let db = try makeDatabase()
        let oldID = UUID()
        let newID = UUID()

        try db.write { database in
            try insertSessionSQL(
                in: database, id: oldID,
                startedAt: Date(timeIntervalSinceReferenceDate: 1000)
            )
            try insertSessionSQL(
                in: database, id: newID,
                startedAt: Date(timeIntervalSinceReferenceDate: 5000)
            )
        }

        let latest = try db.read { database in
            try LogQueries.latestSessionID(db: database)
        }

        #expect(latest == newID)
    }

    @Test("latestSessionID returns nil when no sessions")
    func latestSessionIDEmpty() throws {
        let db = try makeDatabase()
        let latest = try db.read { database in
            try LogQueries.latestSessionID(db: database)
        }
        #expect(latest == nil)
    }

    // MARK: - fetchErrors

    @Test("fetchErrors returns only error and critical entries")
    func fetchErrorsFiltersCorrectly() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .debug, message: "Debug")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .info, message: "Info")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .warning, message: "Warning")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .error, message: "Error")
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .critical, message: "Critical")
        }

        let errors = try db.read { database in
            try LogQueries.fetchErrors(db: database, sessionID: sessionID)
        }

        #expect(errors.count == 2)
        let messages = Set(errors.map { $0.message })
        #expect(messages.contains("Error"))
        #expect(messages.contains("Critical"))
    }

    @Test("fetchErrors returns empty when no errors exist")
    func fetchErrorsEmpty() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, level: .info, message: "All good")
        }

        let errors = try db.read { database in
            try LogQueries.fetchErrors(db: database, sessionID: sessionID)
        }

        #expect(errors.isEmpty)
    }

    @Test("fetchErrors respects limit")
    func fetchErrorsLimit() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            for i in 0..<10 {
                _ = try insertLogEntry(
                    in: database, sessionID: sessionID, level: .error,
                    message: "Error \(i)"
                )
            }
        }

        let errors = try db.read { database in
            try LogQueries.fetchErrors(db: database, sessionID: sessionID, limit: 3)
        }

        #expect(errors.count == 3)
    }
}
