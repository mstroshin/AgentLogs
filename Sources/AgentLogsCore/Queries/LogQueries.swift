import Foundation
import GRDB

public enum LogQueries: Sendable {
    public static func fetchSessions(
        db: Database,
        crashedOnly: Bool = false,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [Session] {
        var sql = "SELECT * FROM session"
        var arguments: [DatabaseValueConvertible] = []

        if crashedOnly {
            sql += " WHERE isCrashed = ?"
            arguments.append(true)
        }

        sql += " ORDER BY startedAt DESC LIMIT ? OFFSET ?"
        arguments.append(limit)
        arguments.append(offset)

        return try Session.fetchAll(
            db,
            sql: sql,
            arguments: StatementArguments(arguments)
        )
    }

    public static func fetchLogs(
        db: Database,
        sessionID: UUID,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        sinceTimestamp: Date? = nil,
        limit: Int = 500
    ) throws -> [LogEntry] {
        var conditions: [String] = ["sessionID = ?"]
        var arguments: [DatabaseValueConvertible] = [sessionID.uuidString]

        if let category {
            conditions.append("category = ?")
            arguments.append(category.rawValue)
        }

        if let level {
            conditions.append("level = ?")
            arguments.append(level.rawValue)
        }

        if let sinceTimestamp {
            conditions.append("timestamp > ?")
            arguments.append(sinceTimestamp.timeIntervalSinceReferenceDate)
        }

        let whereClause = conditions.joined(separator: " AND ")
        let sql = "SELECT * FROM logEntry WHERE \(whereClause) ORDER BY timestamp ASC LIMIT ?"
        arguments.append(limit)

        return try LogEntry.fetchAll(
            db,
            sql: sql,
            arguments: StatementArguments(arguments)
        )
    }

    public static func tailLogs(
        db: Database,
        sessionID: UUID,
        afterID: Int
    ) throws -> [LogEntry] {
        return try LogEntry.fetchAll(
            db,
            sql: "SELECT * FROM logEntry WHERE sessionID = ? AND id > ? ORDER BY id ASC",
            arguments: [sessionID.uuidString, afterID]
        )
    }

    public static func fetchHTTPEntry(
        db: Database,
        logEntryID: Int
    ) throws -> HTTPEntry? {
        return try HTTPEntry.fetchOne(
            db,
            sql: "SELECT * FROM httpEntry WHERE logEntryID = ?",
            arguments: [logEntryID]
        )
    }

    public static func searchLogs(
        db: Database,
        query: String,
        sessionID: UUID? = nil,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        limit: Int = 100
    ) throws -> [LogEntry] {
        var conditions: [String] = ["message LIKE ?"]
        var arguments: [DatabaseValueConvertible] = ["%\(query)%"]

        if let sessionID {
            conditions.append("sessionID = ?")
            arguments.append(sessionID.uuidString)
        }

        if let category {
            conditions.append("category = ?")
            arguments.append(category.rawValue)
        }

        if let level {
            conditions.append("level = ?")
            arguments.append(level.rawValue)
        }

        let whereClause = conditions.joined(separator: " AND ")
        let sql = "SELECT * FROM logEntry WHERE \(whereClause) ORDER BY timestamp DESC LIMIT ?"
        arguments.append(limit)

        return try LogEntry.fetchAll(
            db,
            sql: sql,
            arguments: StatementArguments(arguments)
        )
    }

    public static func latestSessionID(db: Database) throws -> UUID? {
        let session = try Session.fetchOne(
            db,
            sql: "SELECT * FROM session ORDER BY startedAt DESC LIMIT 1"
        )
        return session?.id
    }

    public static func fetchErrors(
        db: Database,
        sessionID: UUID,
        limit: Int = 100
    ) throws -> [LogEntry] {
        return try LogEntry.fetchAll(
            db,
            sql: """
                SELECT * FROM logEntry
                WHERE sessionID = ? AND level IN (?, ?)
                ORDER BY timestamp DESC LIMIT ?
                """,
            arguments: [
                sessionID.uuidString,
                LogLevel.error.rawValue,
                LogLevel.critical.rawValue,
                limit,
            ]
        )
    }
}
