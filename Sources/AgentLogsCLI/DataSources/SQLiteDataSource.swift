import Foundation
import GRDB
import AgentLogsCore

struct SQLiteDataSource: LogDataSource, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    init(path: String) throws {
        self.dbQueue = try DatabaseSetup.openDatabase(at: path)
    }

    func fetchSessions(crashedOnly: Bool, limit: Int) throws -> [Session] {
        try dbQueue.read { db in
            try LogQueries.fetchSessions(db: db, crashedOnly: crashedOnly, limit: limit)
        }
    }

    func fetchLogs(sessionID: UUID, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        try dbQueue.read { db in
            try LogQueries.fetchLogs(db: db, sessionID: sessionID, category: category, level: level, limit: limit)
        }
    }

    func tailLogs(sessionID: UUID, afterID: Int) throws -> [LogEntry] {
        try dbQueue.read { db in
            try LogQueries.tailLogs(db: db, sessionID: sessionID, afterID: afterID)
        }
    }

    func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry? {
        try dbQueue.read { db in
            try LogQueries.fetchHTTPEntry(db: db, logEntryID: logEntryID)
        }
    }

    func searchLogs(query: String, sessionID: UUID?, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        try dbQueue.read { db in
            try LogQueries.searchLogs(db: db, query: query, sessionID: sessionID, category: category, level: level, limit: limit)
        }
    }

    func latestSessionID() throws -> UUID? {
        try dbQueue.read { db in
            try LogQueries.latestSessionID(db: db)
        }
    }
}
