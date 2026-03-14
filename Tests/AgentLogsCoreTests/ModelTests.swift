import Testing
import Foundation
import CoreData
@testable import AgentLogsCore

@Suite("Model Records")
struct ModelTests {

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
        appName: String = "TestApp",
        appVersion: String? = "1.0",
        bundleID: String? = "com.test.app",
        osName: String = "macOS",
        osVersion: String = "15.0.0",
        deviceModel: String = "MacBookPro",
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1000),
        endedAt: Date? = nil,
        isCrashed: Bool = false
    ) -> CDSession {
        let session = CDSession(context: context)
        session.id = id
        session.appName = appName
        session.appVersion = appVersion
        session.bundleID = bundleID
        session.osName = osName
        session.osVersion = osVersion
        session.deviceModel = deviceModel
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.isCrashed = isCrashed
        return session
    }

    private func insertLogEntry(
        in context: NSManagedObjectContext,
        session: CDSession,
        sequenceID: Int64 = 1,
        category: LogCategory = .manualLogs,
        level: LogLevel = .info,
        message: String = "Test message",
        timestamp: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) -> CDLogEntry {
        let entry = CDLogEntry(context: context)
        entry.sequenceID = sequenceID
        entry.timestamp = timestamp
        entry.category = category.rawValue
        entry.level = level.rawValue
        entry.message = message
        entry.sourceFile = "Test.swift"
        entry.sourceLine = 42
        entry.session = session
        return entry
    }

    // MARK: - Session Tests

    @Test("Session can be inserted and fetched")
    func sessionInsertAndFetch() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        _ = insertSession(in: context, id: sessionID)
        try context.save()

        let request = NSFetchRequest<CDSession>(entityName: "CDSession")
        request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        let fetched = try context.fetch(request).first

        #expect(fetched != nil)
        #expect(fetched?.id == sessionID)
        #expect(fetched?.appName == "TestApp")
        #expect(fetched?.appVersion == "1.0")
        #expect(fetched?.bundleID == "com.test.app")
        #expect(fetched?.osName == "macOS")
        #expect(fetched?.osVersion == "15.0.0")
        #expect(fetched?.deviceModel == "MacBookPro")
        #expect(fetched?.isCrashed == false)
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

    @Test("Session can be updated")
    func sessionUpdate() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        try context.save()

        cdSession.endedAt = Date(timeIntervalSinceReferenceDate: 2000)
        cdSession.isCrashed = true
        try context.save()

        let request = NSFetchRequest<CDSession>(entityName: "CDSession")
        request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        let fetched = try context.fetch(request).first

        #expect(fetched?.isCrashed == true)
        #expect(fetched?.endedAt != nil)
    }

    // MARK: - LogEntry Tests

    @Test("LogEntry can be inserted and fetched")
    func logEntryInsertAndFetch() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        let cdEntry = insertLogEntry(in: context, session: cdSession, message: "Hello world")
        try context.save()

        let logEntry = cdEntry.toLogEntry()
        #expect(logEntry.id == 1)
        #expect(logEntry.message == "Hello world")
        #expect(logEntry.category == .manualLogs)
        #expect(logEntry.level == .info)
        #expect(logEntry.sourceFile == "Test.swift")
        #expect(logEntry.sourceLine == 42)
    }

    @Test("Multiple log entries can be inserted for one session")
    func multipleLogEntries() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        _ = insertLogEntry(in: context, session: cdSession, sequenceID: 1, message: "First")
        _ = insertLogEntry(in: context, session: cdSession, sequenceID: 2, message: "Second")
        _ = insertLogEntry(in: context, session: cdSession, sequenceID: 3, message: "Third")
        try context.save()

        let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
        let count = try context.count(for: request)
        #expect(count == 3)
    }

    // MARK: - HTTPEntry Tests

    @Test("HTTPEntry can be inserted and fetched")
    func httpEntryInsertAndFetch() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        let cdLogEntry = insertLogEntry(in: context, session: cdSession, category: .http)

        let cdHTTP = CDHTTPEntry(context: context)
        cdHTTP.method = "GET"
        cdHTTP.url = "https://api.example.com/data"
        cdHTTP.requestHeaders = "{\"Accept\": \"application/json\"}"
        cdHTTP.statusCode = 200
        cdHTTP.responseHeaders = "{\"Content-Type\": \"application/json\"}"
        cdHTTP.responseBody = "{\"ok\": true}"
        cdHTTP.durationMs = 123.45
        cdHTTP.logEntry = cdLogEntry
        try context.save()

        let httpEntry = cdHTTP.toHTTPEntry()
        #expect(httpEntry.method == "GET")
        #expect(httpEntry.url == "https://api.example.com/data")
        #expect(httpEntry.statusCode == 200)
        #expect(httpEntry.durationMs == 123.45)
        #expect(httpEntry.responseBody == "{\"ok\": true}")
    }

    // MARK: - Cascade Delete Tests

    @Test("Deleting session cascades to log entries")
    func cascadeDeleteSessionToLogEntries() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        _ = insertLogEntry(in: context, session: cdSession, sequenceID: 1, message: "Entry 1")
        _ = insertLogEntry(in: context, session: cdSession, sequenceID: 2, message: "Entry 2")
        try context.save()

        let countBefore = try context.count(for: NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry"))
        #expect(countBefore == 2)

        context.delete(cdSession)
        try context.save()

        let countAfter = try context.count(for: NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry"))
        #expect(countAfter == 0)
    }

    @Test("Deleting log entry cascades to HTTP entry")
    func cascadeDeleteLogEntryToHTTPEntry() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let sessionID = UUID()

        let cdSession = insertSession(in: context, id: sessionID)
        let cdLogEntry = insertLogEntry(in: context, session: cdSession, category: .http)

        let cdHTTP = CDHTTPEntry(context: context)
        cdHTTP.method = "POST"
        cdHTTP.url = "https://api.example.com/submit"
        cdHTTP.statusCode = 201
        cdHTTP.durationMs = 50.0
        cdHTTP.logEntry = cdLogEntry
        try context.save()

        let httpBefore = try context.count(for: NSFetchRequest<CDHTTPEntry>(entityName: "CDHTTPEntry"))
        #expect(httpBefore == 1)

        context.delete(cdLogEntry)
        try context.save()

        let httpAfter = try context.count(for: NSFetchRequest<CDHTTPEntry>(entityName: "CDHTTPEntry"))
        #expect(httpAfter == 0)
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
        // Backward compatibility: old "custom" entries decode correctly
        #expect(LogCategory(rawValue: "custom").rawValue == "custom")
    }

    // MARK: - toSession / toLogEntry / toHTTPEntry

    @Test("CDSession.toSession produces correct struct")
    func cdSessionToStruct() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let id = UUID()
        let cdSession = insertSession(in: context, id: id, appName: "ConvertTest")
        try context.save()

        let session = cdSession.toSession()
        #expect(session.id == id)
        #expect(session.appName == "ConvertTest")
    }
}
