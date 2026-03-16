import Foundation
import AgentLogsCore

struct SQLiteDataSourceImpl: LogDataSource, Sendable {
    let store: SQLiteStore

    init(path: String) throws {
        self.store = try SQLiteStore(path: path)
    }

    func fetchSessions(crashedOnly: Bool, limit: Int) throws -> [Session] {
        try store.fetchSessions(crashedOnly: crashedOnly, limit: limit)
    }

    func fetchLogs(sessionID: UUID, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        try store.fetchLogs(sessionID: sessionID, category: category, level: level, limit: limit)
    }

    func tailLogs(sessionID: UUID, afterID: Int) throws -> [LogEntry] {
        try store.tailLogs(sessionID: sessionID, afterID: afterID)
    }

    func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry? {
        try store.fetchHTTPEntry(logEntryID: logEntryID)
    }

    func searchLogs(query: String, sessionID: UUID?, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        try store.searchLogs(query: query, sessionID: sessionID, category: category, level: level, limit: limit)
    }

    func latestSessionID() throws -> UUID? {
        try store.latestSessionID()
    }
}
