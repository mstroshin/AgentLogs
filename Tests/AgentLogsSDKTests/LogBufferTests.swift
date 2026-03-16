import Testing
import Foundation
@testable import AgentLogsSDK
import AgentLogsCore

@Suite("LogBuffer")
struct LogBufferTests {

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore()
    }

    private func insertSession(store: SQLiteStore, sessionID: UUID) throws {
        try store.insertSession(Session(
            id: sessionID,
            appName: "TestApp",
            osName: "macOS",
            osVersion: "15.0",
            deviceModel: "Mac"
        ))
    }

    private func makePendingEntry(
        sessionID: UUID,
        message: String = "Test message",
        category: LogCategory = .manualLogs,
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
            sourceLine: 1
        )
    }

    @Test("Buffer accumulates entries and flush writes to database")
    func flushWritesToDatabase() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        try insertSession(store: store, sessionID: sessionID)

        let buffer = LogBuffer(store: store)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 1"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 2"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 3"))

        await buffer.flush()

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 3)
    }

    @Test("Buffer writes when threshold reached (50 entries)")
    func bufferAutoFlushesAtThreshold() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        try insertSession(store: store, sessionID: sessionID)

        let buffer = LogBuffer(store: store)

        for i in 0..<50 {
            await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry \(i)"))
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 50)
    }

    @Test("Flush with empty buffer does not crash")
    func flushEmptyBuffer() async throws {
        let store = try makeStore()
        let buffer = LogBuffer(store: store)
        await buffer.flush()
        #expect(Bool(true))
    }

    @Test("Stop flushes remaining entries")
    func stopFlushesRemaining() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        try insertSession(store: store, sessionID: sessionID)

        let buffer = LogBuffer(store: store)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Before stop"))
        await buffer.stop()

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 1)
    }

    @Test("Buffer flushes HTTP entries alongside log entries")
    func flushWithHTTPEntry() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        try insertSession(store: store, sessionID: sessionID)

        let buffer = LogBuffer(store: store)

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

        let logs = try store.fetchLogs(sessionID: sessionID)
        #expect(logs.count == 1)

        let httpEntry = try store.fetchHTTPEntry(logEntryID: logs[0].id)
        #expect(httpEntry != nil)
        #expect(httpEntry?.method == "GET")
    }
}
