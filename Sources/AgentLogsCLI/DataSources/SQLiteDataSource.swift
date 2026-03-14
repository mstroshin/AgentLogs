import Foundation
import CoreData
import AgentLogsCore

struct CoreDataDataSource: LogDataSource, Sendable {
    let container: NSPersistentContainer

    init(path: String) throws {
        let storeURL = URL(fileURLWithPath: path)
        let container = CoreDataStack.createContainer(at: storeURL)

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }

        self.container = container
    }

    func fetchSessions(crashedOnly: Bool, limit: Int) throws -> [Session] {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.fetchSessions(context: context, crashedOnly: crashedOnly, limit: limit)
        }
    }

    func fetchLogs(sessionID: UUID, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.fetchLogs(context: context, sessionID: sessionID, category: category, level: level, limit: limit)
        }
    }

    func tailLogs(sessionID: UUID, afterID: Int) throws -> [LogEntry] {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.tailLogs(context: context, sessionID: sessionID, afterID: afterID)
        }
    }

    func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry? {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.fetchHTTPEntry(context: context, logEntryID: logEntryID)
        }
    }

    func searchLogs(query: String, sessionID: UUID?, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.searchLogs(context: context, query: query, sessionID: sessionID, category: category, level: level, limit: limit)
        }
    }

    func latestSessionID() throws -> UUID? {
        let context = container.viewContext
        return try context.performAndWait {
            try LogQueries.latestSessionID(context: context)
        }
    }
}
