import Testing
import Foundation
import CoreData
@testable import AgentLogsSDK
import AgentLogsCore

@Suite("LogBuffer")
struct LogBufferTests {

    private func makeContainer() throws -> NSPersistentContainer {
        let container = CoreDataStack.createInMemoryContainer()
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    private func insertSession(container: NSPersistentContainer, sessionID: UUID) throws {
        let context = container.viewContext
        let session = CDSession(context: context)
        session.id = sessionID
        session.appName = "TestApp"
        session.osName = "macOS"
        session.osVersion = "15.0"
        session.deviceModel = "Mac"
        session.startedAt = Date()
        try context.save()
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

    private func logEntryCount(container: NSPersistentContainer) throws -> Int {
        let context = container.viewContext
        return try context.performAndWait {
            try context.count(for: NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry"))
        }
    }

    private func httpEntryCount(container: NSPersistentContainer) throws -> Int {
        let context = container.viewContext
        return try context.performAndWait {
            try context.count(for: NSFetchRequest<CDHTTPEntry>(entityName: "CDHTTPEntry"))
        }
    }

    @Test("Buffer accumulates entries and flush writes to database")
    func flushWritesToDatabase() async throws {
        let container = try makeContainer()
        let sessionID = UUID()
        try insertSession(container: container, sessionID: sessionID)

        let bgContext = container.newBackgroundContext()
        let buffer = LogBuffer(context: bgContext)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 1"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 2"))
        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry 3"))

        await buffer.flush()

        try await Task.sleep(nanoseconds: 500_000_000)

        // Refresh view context to see background changes
        container.viewContext.refreshAllObjects()
        let count = try logEntryCount(container: container)
        #expect(count == 3)
    }

    @Test("Buffer writes when threshold reached (50 entries)")
    func bufferAutoFlushesAtThreshold() async throws {
        let container = try makeContainer()
        let sessionID = UUID()
        try insertSession(container: container, sessionID: sessionID)

        let bgContext = container.newBackgroundContext()
        let buffer = LogBuffer(context: bgContext)

        for i in 0..<50 {
            await buffer.append(makePendingEntry(sessionID: sessionID, message: "Entry \(i)"))
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)

        container.viewContext.refreshAllObjects()
        let count = try logEntryCount(container: container)
        #expect(count == 50)
    }

    @Test("Flush with empty buffer does not crash")
    func flushEmptyBuffer() async throws {
        let container = try makeContainer()
        let bgContext = container.newBackgroundContext()
        let buffer = LogBuffer(context: bgContext)
        await buffer.flush()
        #expect(Bool(true))
    }

    @Test("Stop flushes remaining entries")
    func stopFlushesRemaining() async throws {
        let container = try makeContainer()
        let sessionID = UUID()
        try insertSession(container: container, sessionID: sessionID)

        let bgContext = container.newBackgroundContext()
        let buffer = LogBuffer(context: bgContext)

        await buffer.append(makePendingEntry(sessionID: sessionID, message: "Before stop"))
        await buffer.stop()

        try await Task.sleep(nanoseconds: 500_000_000)

        container.viewContext.refreshAllObjects()
        let count = try logEntryCount(container: container)
        #expect(count == 1)
    }

    @Test("Buffer flushes HTTP entries alongside log entries")
    func flushWithHTTPEntry() async throws {
        let container = try makeContainer()
        let sessionID = UUID()
        try insertSession(container: container, sessionID: sessionID)

        let bgContext = container.newBackgroundContext()
        let buffer = LogBuffer(context: bgContext)

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

        try await Task.sleep(nanoseconds: 500_000_000)

        container.viewContext.refreshAllObjects()
        let logCount = try logEntryCount(container: container)
        let httpCount = try httpEntryCount(container: container)

        #expect(logCount == 1)
        #expect(httpCount == 1)
    }
}
