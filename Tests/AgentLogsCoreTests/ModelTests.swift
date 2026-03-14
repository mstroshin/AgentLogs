import Testing
import Foundation
import GRDB
@testable import AgentLogsCore

@Suite("Model GRDB Records")
struct ModelTests {

    private func makeDatabase() throws -> DatabaseQueue {
        try DatabaseSetup.openInMemoryDatabase()
    }

    /// Insert a session using raw SQL with uuidString to match the production query patterns.
    private func insertSessionSQL(
        in db: Database,
        id: UUID = UUID(),
        appName: String = "TestApp",
        appVersion: String? = "1.0",
        bundleID: String? = "com.test.app",
        osName: String = "macOS",
        osVersion: String = "15.0.0",
        deviceModel: String = "MacBookPro",
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1000),
        endedAt: Date? = nil,
        isCrashed: Bool = false
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO session (id, appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString,
                appName,
                appVersion,
                bundleID,
                osName,
                osVersion,
                deviceModel,
                startedAt.timeIntervalSinceReferenceDate,
                endedAt?.timeIntervalSinceReferenceDate,
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

    // MARK: - Session Tests

    @Test("Session can be inserted and fetched via raw SQL")
    func sessionInsertAndFetch() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
        }

        let fetched = try db.read { database in
            try Row.fetchOne(database, sql: "SELECT * FROM session WHERE id = ?", arguments: [sessionID.uuidString])
        }

        #expect(fetched != nil)
        #expect((fetched?["id"] as? String) == sessionID.uuidString)
        #expect((fetched?["appName"] as? String) == "TestApp")
        #expect((fetched?["appVersion"] as? String) == "1.0")
        #expect((fetched?["bundleID"] as? String) == "com.test.app")
        #expect((fetched?["osName"] as? String) == "macOS")
        #expect((fetched?["osVersion"] as? String) == "15.0.0")
        #expect((fetched?["deviceModel"] as? String) == "MacBookPro")
        // SQLite stores Bool as integer 0/1
        #expect((fetched?["isCrashed"] as? Int64) == 0)
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

    @Test("Session can be updated via raw SQL")
    func sessionUpdate() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
        }

        let endedAt = Date(timeIntervalSinceReferenceDate: 2000)
        try db.write { database in
            try database.execute(
                sql: "UPDATE session SET endedAt = ?, isCrashed = ? WHERE id = ?",
                arguments: [endedAt.timeIntervalSinceReferenceDate, true, sessionID.uuidString]
            )
        }

        let fetched = try db.read { database in
            try Row.fetchOne(database, sql: "SELECT * FROM session WHERE id = ?", arguments: [sessionID.uuidString])
        }
        #expect((fetched?["isCrashed"] as? Int64) == 1)
        #expect(fetched?["endedAt"] != nil)
    }

    // MARK: - LogEntry Tests

    @Test("LogEntry can be inserted and fetched")
    func logEntryInsertAndFetch() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        let logEntryID = try db.write { database -> Int in
            try insertSessionSQL(in: database, id: sessionID)
            return try insertLogEntry(in: database, sessionID: sessionID, message: "Hello world")
        }

        let fetched = try db.read { database in
            try LogEntry.fetchOne(database, key: logEntryID)
        }

        #expect(fetched != nil)
        #expect(fetched?.id == logEntryID)
        #expect(fetched?.message == "Hello world")
        #expect(fetched?.category == .custom)
        #expect(fetched?.level == .info)
        #expect(fetched?.sourceFile == "Test.swift")
        #expect(fetched?.sourceLine == 42)
    }

    @Test("Multiple log entries can be inserted for one session")
    func multipleLogEntries() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "First")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Second")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Third")
        }

        let count = try db.read { database in
            try LogEntry.fetchCount(database)
        }
        #expect(count == 3)
    }

    // MARK: - HTTPEntry Tests

    @Test("HTTPEntry can be inserted and fetched")
    func httpEntryInsertAndFetch() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        let logEntryID = try db.write { database -> Int in
            try insertSessionSQL(in: database, id: sessionID)
            let entryID = try insertLogEntry(in: database, sessionID: sessionID, category: .http)

            let httpEntry = HTTPEntry(
                logEntryID: entryID,
                method: "GET",
                url: "https://api.example.com/data",
                requestHeaders: "{\"Accept\": \"application/json\"}",
                requestBody: nil,
                statusCode: 200,
                responseHeaders: "{\"Content-Type\": \"application/json\"}",
                responseBody: "{\"ok\": true}",
                durationMs: 123.45
            )
            try httpEntry.insert(database)
            return entryID
        }

        let fetched = try db.read { database in
            try HTTPEntry.fetchOne(database, key: logEntryID)
        }

        #expect(fetched != nil)
        #expect(fetched?.logEntryID == logEntryID)
        #expect(fetched?.method == "GET")
        #expect(fetched?.url == "https://api.example.com/data")
        #expect(fetched?.statusCode == 200)
        #expect(fetched?.durationMs == 123.45)
        #expect(fetched?.responseBody == "{\"ok\": true}")
    }

    // MARK: - Cascade Delete Tests

    @Test("Deleting session cascades to log entries")
    func cascadeDeleteSessionToLogEntries() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        try db.write { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try insertSessionSQL(in: database, id: sessionID)
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Entry 1")
            _ = try insertLogEntry(in: database, sessionID: sessionID, message: "Entry 2")
        }

        let countBefore = try db.read { database in
            try LogEntry.fetchCount(database)
        }
        #expect(countBefore == 2)

        try db.write { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "DELETE FROM session WHERE id = ?", arguments: [sessionID.uuidString])
        }

        let countAfter = try db.read { database in
            try LogEntry.fetchCount(database)
        }
        #expect(countAfter == 0)
    }

    @Test("Deleting log entry cascades to HTTP entry")
    func cascadeDeleteLogEntryToHTTPEntry() throws {
        let db = try makeDatabase()
        let sessionID = UUID()

        let logEntryID = try db.write { database -> Int in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try insertSessionSQL(in: database, id: sessionID)
            let entryID = try insertLogEntry(in: database, sessionID: sessionID, category: .http)
            let httpEntry = HTTPEntry(
                logEntryID: entryID,
                method: "POST",
                url: "https://api.example.com/submit",
                statusCode: 201,
                durationMs: 50.0
            )
            try httpEntry.insert(database)
            return entryID
        }

        let httpBefore = try db.read { database in
            try HTTPEntry.fetchOne(database, key: logEntryID)
        }
        #expect(httpBefore != nil)

        try db.write { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            _ = try LogEntry.deleteOne(database, key: logEntryID)
        }

        let httpAfter = try db.read { database in
            try HTTPEntry.fetchOne(database, key: logEntryID)
        }
        #expect(httpAfter == nil)
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
        #expect(LogCategory.custom.rawValue == "custom")
    }
}
