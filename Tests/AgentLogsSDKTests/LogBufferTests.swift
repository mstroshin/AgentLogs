import Testing
import Foundation
import GRDB
@testable import AgentLogsSDK
import AgentLogsCore

@Suite("LogBuffer")
struct LogBufferTests {

    private func makeDatabase() throws -> DatabaseQueue {
        try DatabaseSetup.openInMemoryDatabase()
    }

    /// Insert a session using raw SQL with uuidString to match the production LogBuffer patterns.
    private func insertSessionSQL(db: DatabaseQueue, sessionID: UUID) async throws {
        try await db.write { database in
            try database.execute(
                sql: """
                    INSERT INTO session (id, appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed)
                    VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, NULL, ?)
                    """,
                arguments: [
                    sessionID.uuidString,
                    "TestApp",
                    "macOS",
                    "15.0",
                    "Mac",
                    Date().timeIntervalSinceReferenceDate,
                    false,
                ]
            )
        }
    }

    private func makePendingEntry(
        sessionID: UUID,
        message: String = "Test message",
        category: LogCategory = .custom,
        level: LogLevel = .info
    ) -> PendingLogEntry {
        PendingLogEntry(
            sessionID: sessionID,
            timestamp: Date(),
            category: category,
            level: level,
            message: message,
            metadata: nil,
            sourceFile: "Test.swift",
            sourceLine: 1,
            httpEntry: nil
        )
    }

    private func logEntryCount(db: DatabaseQueue) async throws -> Int {
        try await db.read { database in
            try LogEntry.fetchCount(database)
        }
    }

    private func httpEntryCount(db: DatabaseQueue) async throws -> Int {
        try await db.read { database in
            try HTTPEntry.fetchCount(database)
        }
    }

    @Test("Buffer accumulates entries and flush writes to database")
    func flushWritesToDatabase() async throws {
        let db = try makeDatabase()
        let sessionID = UUID()
        try await insertSessionSQL(db: db, sessionID: sessionID)

        let buffer = LogBuffer(dbQueue: db)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 1"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 2"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 3"))

        await buffer.flush()

        // Give the detached Task time to complete the write
        try await Task.sleep(nanoseconds: 500_000_000)

        let count = try await logEntryCount(db: db)
        #expect(count == 3)
    }

    @Test("Buffer writes when threshold reached (50 entries)")
    func bufferAutoFlushesAtThreshold() async throws {
        let db = try makeDatabase()
        let sessionID = UUID()
        try await insertSessionSQL(db: db, sessionID: sessionID)

        let buffer = LogBuffer(dbQueue: db)

        for i in 0..<50 {
            await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry \(i)"))
        }

        // Give the detached Task time to complete the write
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let count = try await logEntryCount(db: db)
        #expect(count == 50)
    }

    @Test("Flush with empty buffer does not crash")
    func flushEmptyBuffer() async throws {
        let db = try makeDatabase()
        let buffer = LogBuffer(dbQueue: db)
        await buffer.flush()
        #expect(Bool(true))
    }

    @Test("Stop flushes remaining entries")
    func stopFlushesRemaining() async throws {
        let db = try makeDatabase()
        let sessionID = UUID()
        try await insertSessionSQL(db: db, sessionID: sessionID)

        let buffer = LogBuffer(dbQueue: db)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Before stop"))
        await buffer.stop()

        // Give the detached Task time to complete the write
        try await Task.sleep(nanoseconds: 500_000_000)

        let count = try await logEntryCount(db: db)
        #expect(count == 1)
    }

    @Test("Buffer flushes HTTP entries alongside log entries")
    func flushWithHTTPEntry() async throws {
        let db = try makeDatabase()
        let sessionID = UUID()
        try await insertSessionSQL(db: db, sessionID: sessionID)

        let buffer = LogBuffer(dbQueue: db)

        let entry = PendingLogEntry(
            sessionID: sessionID,
            timestamp: Date(),
            category: .http,
            level: .info,
            message: "GET /api/data",
            metadata: nil,
            sourceFile: nil,
            sourceLine: nil,
            httpEntry: PendingHTTPEntry(
                method: "GET",
                url: "https://api.example.com/data",
                requestHeaders: nil,
                requestBody: nil,
                statusCode: 200,
                responseHeaders: nil,
                responseBody: "{\"ok\":true}",
                durationMs: 42.0
            )
        )

        await buffer.append(entry)
        await buffer.flush()

        // Give the detached Task time to complete the write
        try await Task.sleep(nanoseconds: 500_000_000)

        let logCount = try await logEntryCount(db: db)
        let httpCount = try await httpEntryCount(db: db)

        #expect(logCount == 1)
        #expect(httpCount == 1)
    }
}
