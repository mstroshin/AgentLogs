import Foundation
import CoreData

public enum LogQueries: Sendable {

    public static func fetchSessions(
        context: NSManagedObjectContext,
        crashedOnly: Bool = false,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [Session] {
        let request = NSFetchRequest<CDSession>(entityName: "CDSession")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset

        if crashedOnly {
            request.predicate = NSPredicate(format: "isCrashed == YES")
        }

        let results = try context.fetch(request)
        return results.map { $0.toSession() }
    }

    public static func fetchLogs(
        context: NSManagedObjectContext,
        sessionID: UUID,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        sinceTimestamp: Date? = nil,
        limit: Int = 500
    ) throws -> [LogEntry] {
        let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.fetchLimit = limit

        var predicates: [NSPredicate] = [
            NSPredicate(format: "session.id == %@", sessionID as CVarArg)
        ]

        if let category {
            predicates.append(NSPredicate(format: "category == %@", category.rawValue))
        }
        if let level {
            predicates.append(NSPredicate(format: "level == %@", level.rawValue))
        }
        if let sinceTimestamp {
            predicates.append(NSPredicate(format: "timestamp > %@", sinceTimestamp as NSDate))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let results = try context.fetch(request)
        return results.map { $0.toLogEntry() }
    }

    public static func tailLogs(
        context: NSManagedObjectContext,
        sessionID: UUID,
        afterID: Int
    ) throws -> [LogEntry] {
        let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "sequenceID", ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "session.id == %@", sessionID as CVarArg),
            NSPredicate(format: "sequenceID > %lld", Int64(afterID)),
        ])

        let results = try context.fetch(request)
        return results.map { $0.toLogEntry() }
    }

    public static func fetchHTTPEntry(
        context: NSManagedObjectContext,
        logEntryID: Int
    ) throws -> HTTPEntry? {
        let request = NSFetchRequest<CDHTTPEntry>(entityName: "CDHTTPEntry")
        request.predicate = NSPredicate(format: "logEntry.sequenceID == %lld", Int64(logEntryID))
        request.fetchLimit = 1

        return try context.fetch(request).first?.toHTTPEntry()
    }

    public static func searchLogs(
        context: NSManagedObjectContext,
        query: String,
        sessionID: UUID? = nil,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        limit: Int = 100
    ) throws -> [LogEntry] {
        let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit

        var predicates: [NSPredicate] = [
            NSPredicate(format: "message CONTAINS[cd] %@", query)
        ]

        if let sessionID {
            predicates.append(NSPredicate(format: "session.id == %@", sessionID as CVarArg))
        }
        if let category {
            predicates.append(NSPredicate(format: "category == %@", category.rawValue))
        }
        if let level {
            predicates.append(NSPredicate(format: "level == %@", level.rawValue))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let results = try context.fetch(request)
        return results.map { $0.toLogEntry() }
    }

    public static func latestSessionID(context: NSManagedObjectContext) throws -> UUID? {
        let request = NSFetchRequest<CDSession>(entityName: "CDSession")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.fetchLimit = 1

        return try context.fetch(request).first?.id
    }

    public static func fetchErrors(
        context: NSManagedObjectContext,
        sessionID: UUID,
        limit: Int = 100
    ) throws -> [LogEntry] {
        let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "session.id == %@", sessionID as CVarArg),
            NSPredicate(format: "level IN %@", [LogLevel.error.rawValue, LogLevel.critical.rawValue]),
        ])

        let results = try context.fetch(request)
        return results.map { $0.toLogEntry() }
    }
}
