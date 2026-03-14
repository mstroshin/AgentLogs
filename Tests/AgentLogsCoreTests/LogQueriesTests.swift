import Testing
import Foundation
import CoreData
import os
@testable import AgentLogsCore

@Suite("LogQueries")
struct LogQueriesTests {

    private func makeContainer() throws -> NSPersistentContainer {
        let container = CoreDataStack.createInMemoryContainer()
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    private func insertSession(
        in context: NSManagedObjectContext,
        id: UUID = UUID(),
        isCrashed: Bool = false,
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) -> CDSession {
        let session = CDSession(context: context)
        session.id = id
        session.appName = "TestApp"
        session.appVersion = "1.0"
        session.bundleID = "com.test.app"
        session.osName = "macOS"
        session.osVersion = "15.0.0"
        session.deviceModel = "MacBookPro"
        session.startedAt = startedAt
        session.isCrashed = isCrashed
        return session
    }

    private static let _seqCounter = OSAllocatedUnfairLock(initialState: Int64(0))

    @discardableResult
    private func insertLogEntry(
        in context: NSManagedObjectContext,
        session: CDSession,
        category: LogCategory = .manualLogs,
        level: LogLevel = .info,
        message: String = "Test message",
        timestamp: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) -> CDLogEntry {
        let seqID = Self._seqCounter.withLock { value -> Int64 in
            value += 1
            return value
        }
        let entry = CDLogEntry(context: context)
        entry.sequenceID = seqID
        entry.timestamp = timestamp
        entry.category = category.rawValue
        entry.level = level.rawValue
        entry.message = message
        entry.sourceFile = "Test.swift"
        entry.sourceLine = 42
        entry.session = session
        return entry
    }

    // MARK: - fetchSessions

    @Test("fetchSessions returns all sessions ordered by startedAt DESC")
    func fetchSessionsAll() throws {
        let container = try makeContainer()
        let context = container.viewContext

        _ = insertSession(in: context, startedAt: Date(timeIntervalSinceReferenceDate: 1000))
        _ = insertSession(in: context, startedAt: Date(timeIntervalSinceReferenceDate: 2000))
        _ = insertSession(in: context, startedAt: Date(timeIntervalSinceReferenceDate: 3000))
        try context.save()

        let sessions = try LogQueries.fetchSessions(context: context)
        #expect(sessions.count == 3)
        #expect(sessions[0].startedAt > sessions[1].startedAt)
        #expect(sessions[1].startedAt > sessions[2].startedAt)
    }

    @Test("fetchSessions with crashedOnly filter")
    func fetchSessionsCrashedOnly() throws {
        let container = try makeContainer()
        let context = container.viewContext

        _ = insertSession(in: context, isCrashed: false)
        _ = insertSession(in: context, isCrashed: true)
        _ = insertSession(in: context, isCrashed: false)
        try context.save()

        let crashed = try LogQueries.fetchSessions(context: context, crashedOnly: true)
        #expect(crashed.count == 1)
        #expect(crashed[0].isCrashed == true)
    }

    @Test("fetchSessions respects limit and offset")
    func fetchSessionsLimitOffset() throws {
        let container = try makeContainer()
        let context = container.viewContext

        for i in 0..<5 {
            _ = insertSession(in: context, startedAt: Date(timeIntervalSinceReferenceDate: Double(i * 1000)))
        }
        try context.save()

        let page = try LogQueries.fetchSessions(context: context, limit: 2, offset: 1)
        #expect(page.count == 2)
    }

    @Test("fetchSessions returns empty array when none exist")
    func fetchSessionsEmpty() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessions = try LogQueries.fetchSessions(context: context)
        #expect(sessions.isEmpty)
    }

    // MARK: - fetchLogs

    @Test("fetchLogs returns entries for given session")
    func fetchLogsForSession() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()
        let otherSessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        let otherSession = insertSession(in: context, id: otherSessionID)
        insertLogEntry(in: context, session: session, message: "Mine")
        insertLogEntry(in: context, session: otherSession, message: "Other")
        try context.save()

        let logs = try LogQueries.fetchLogs(context: context, sessionID: sessionID)
        #expect(logs.count == 1)
        #expect(logs[0].message == "Mine")
    }

    @Test("fetchLogs filters by category")
    func fetchLogsFilterCategory() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, category: .http, message: "HTTP request")
        insertLogEntry(in: context, session: session, category: .manualLogs, message: "Manual log")
        insertLogEntry(in: context, session: session, category: .system, message: "System log")
        try context.save()

        let httpLogs = try LogQueries.fetchLogs(context: context, sessionID: sessionID, category: .http)
        #expect(httpLogs.count == 1)
        #expect(httpLogs[0].message == "HTTP request")
    }

    @Test("fetchLogs filters by level")
    func fetchLogsFilterLevel() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, level: .info, message: "Info")
        insertLogEntry(in: context, session: session, level: .error, message: "Error")
        insertLogEntry(in: context, session: session, level: .debug, message: "Debug")
        try context.save()

        let errors = try LogQueries.fetchLogs(context: context, sessionID: sessionID, level: .error)
        #expect(errors.count == 1)
        #expect(errors[0].message == "Error")
    }

    @Test("fetchLogs filters by sinceTimestamp")
    func fetchLogsFilterTimestamp() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, message: "Old", timestamp: Date(timeIntervalSinceReferenceDate: 1000))
        insertLogEntry(in: context, session: session, message: "New", timestamp: Date(timeIntervalSinceReferenceDate: 3000))
        try context.save()

        let recent = try LogQueries.fetchLogs(
            context: context, sessionID: sessionID,
            sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
        )
        #expect(recent.count == 1)
        #expect(recent[0].message == "New")
    }

    @Test("fetchLogs respects limit")
    func fetchLogsLimit() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        for i in 0..<10 {
            insertLogEntry(in: context, session: session, message: "Entry \(i)",
                          timestamp: Date(timeIntervalSinceReferenceDate: Double(i * 100)))
        }
        try context.save()

        let logs = try LogQueries.fetchLogs(context: context, sessionID: sessionID, limit: 3)
        #expect(logs.count == 3)
    }

    @Test("fetchLogs with combined filters")
    func fetchLogsCombinedFilters() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, category: .http, level: .error,
                      message: "HTTP error old", timestamp: Date(timeIntervalSinceReferenceDate: 1000))
        insertLogEntry(in: context, session: session, category: .http, level: .error,
                      message: "HTTP error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000))
        insertLogEntry(in: context, session: session, category: .manualLogs, level: .error,
                      message: "Manual error new", timestamp: Date(timeIntervalSinceReferenceDate: 3000))
        try context.save()

        let results = try LogQueries.fetchLogs(
            context: context, sessionID: sessionID, category: .http, level: .error,
            sinceTimestamp: Date(timeIntervalSinceReferenceDate: 2000)
        )
        #expect(results.count == 1)
        #expect(results[0].message == "HTTP error new")
    }

    // MARK: - tailLogs

    @Test("tailLogs returns entries after a given ID")
    func tailLogsAfterID() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        let first = insertLogEntry(in: context, session: session, message: "First")
        insertLogEntry(in: context, session: session, message: "Second")
        insertLogEntry(in: context, session: session, message: "Third")
        try context.save()

        let tail = try LogQueries.tailLogs(context: context, sessionID: sessionID, afterID: Int(first.sequenceID))
        #expect(tail.count == 2)
        #expect(tail[0].message == "Second")
        #expect(tail[1].message == "Third")
    }

    @Test("tailLogs returns empty when no new entries")
    func tailLogsEmpty() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        let last = insertLogEntry(in: context, session: session, message: "Only one")
        try context.save()

        let tail = try LogQueries.tailLogs(context: context, sessionID: sessionID, afterID: Int(last.sequenceID))
        #expect(tail.isEmpty)
    }

    // MARK: - fetchHTTPEntry

    @Test("fetchHTTPEntry returns matching entry")
    func fetchHTTPEntryFound() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        let cdLogEntry = insertLogEntry(in: context, session: session, category: .http)

        let cdHTTP = CDHTTPEntry(context: context)
        cdHTTP.method = "POST"
        cdHTTP.url = "https://api.example.com/data"
        cdHTTP.statusCode = 201
        cdHTTP.durationMs = 99.5
        cdHTTP.logEntry = cdLogEntry
        try context.save()

        let fetched = try LogQueries.fetchHTTPEntry(context: context, logEntryID: Int(cdLogEntry.sequenceID))
        #expect(fetched != nil)
        #expect(fetched?.method == "POST")
        #expect(fetched?.url == "https://api.example.com/data")
        #expect(fetched?.statusCode == 201)
    }

    @Test("fetchHTTPEntry returns nil when not found")
    func fetchHTTPEntryNotFound() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let result = try LogQueries.fetchHTTPEntry(context: context, logEntryID: 9999)
        #expect(result == nil)
    }

    // MARK: - searchLogs

    @Test("searchLogs finds entries matching query")
    func searchLogsMatchingQuery() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, message: "User logged in successfully")
        insertLogEntry(in: context, session: session, message: "Network error occurred")
        insertLogEntry(in: context, session: session, message: "User logged out")
        try context.save()

        let results = try LogQueries.searchLogs(context: context, query: "logged")
        #expect(results.count == 2)
    }

    @Test("searchLogs filters by sessionID")
    func searchLogsFilterSession() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionA = UUID()
        let sessionB = UUID()

        let sA = insertSession(in: context, id: sessionA)
        let sB = insertSession(in: context, id: sessionB)
        insertLogEntry(in: context, session: sA, message: "Error in A")
        insertLogEntry(in: context, session: sB, message: "Error in B")
        try context.save()

        let results = try LogQueries.searchLogs(context: context, query: "Error", sessionID: sessionA)
        #expect(results.count == 1)
        #expect(results[0].message == "Error in A")
    }

    @Test("searchLogs filters by category and level")
    func searchLogsFilterCategoryLevel() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, category: .http, level: .error, message: "HTTP failure")
        insertLogEntry(in: context, session: session, category: .manualLogs, level: .error, message: "Manual failure")
        insertLogEntry(in: context, session: session, category: .http, level: .info, message: "HTTP success")
        try context.save()

        let results = try LogQueries.searchLogs(context: context, query: "HTTP", category: .http, level: .error)
        #expect(results.count == 1)
        #expect(results[0].message == "HTTP failure")
    }

    @Test("searchLogs returns empty for non-matching query")
    func searchLogsNoMatch() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, message: "Hello world")
        try context.save()

        let results = try LogQueries.searchLogs(context: context, query: "zzzznotfound")
        #expect(results.isEmpty)
    }

    @Test("searchLogs respects limit")
    func searchLogsLimit() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        for i in 0..<10 {
            insertLogEntry(in: context, session: session, message: "Match item \(i)")
        }
        try context.save()

        let results = try LogQueries.searchLogs(context: context, query: "Match", limit: 3)
        #expect(results.count == 3)
    }

    // MARK: - latestSessionID

    @Test("latestSessionID returns most recent session")
    func latestSessionIDReturnsNewest() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let oldID = UUID()
        let newID = UUID()

        _ = insertSession(in: context, id: oldID, startedAt: Date(timeIntervalSinceReferenceDate: 1000))
        _ = insertSession(in: context, id: newID, startedAt: Date(timeIntervalSinceReferenceDate: 5000))
        try context.save()

        let latest = try LogQueries.latestSessionID(context: context)
        #expect(latest == newID)
    }

    @Test("latestSessionID returns nil when no sessions")
    func latestSessionIDEmpty() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let latest = try LogQueries.latestSessionID(context: context)
        #expect(latest == nil)
    }

    // MARK: - fetchErrors

    @Test("fetchErrors returns only error and critical entries")
    func fetchErrorsFiltersCorrectly() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, level: .debug, message: "Debug")
        insertLogEntry(in: context, session: session, level: .info, message: "Info")
        insertLogEntry(in: context, session: session, level: .warning, message: "Warning")
        insertLogEntry(in: context, session: session, level: .error, message: "Error")
        insertLogEntry(in: context, session: session, level: .critical, message: "Critical")
        try context.save()

        let errors = try LogQueries.fetchErrors(context: context, sessionID: sessionID)
        #expect(errors.count == 2)
        let messages = Set(errors.map { $0.message })
        #expect(messages.contains("Error"))
        #expect(messages.contains("Critical"))
    }

    @Test("fetchErrors returns empty when no errors exist")
    func fetchErrorsEmpty() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        insertLogEntry(in: context, session: session, level: .info, message: "All good")
        try context.save()

        let errors = try LogQueries.fetchErrors(context: context, sessionID: sessionID)
        #expect(errors.isEmpty)
    }

    @Test("fetchErrors respects limit")
    func fetchErrorsLimit() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let session = insertSession(in: context, id: sessionID)
        for i in 0..<10 {
            insertLogEntry(in: context, session: session, level: .error, message: "Error \(i)")
        }
        try context.save()

        let errors = try LogQueries.fetchErrors(context: context, sessionID: sessionID, limit: 3)
        #expect(errors.count == 3)
    }
}
