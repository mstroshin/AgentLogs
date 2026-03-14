import Foundation
import AgentLogsCore

protocol LogDataSource: Sendable {
    func fetchSessions(crashedOnly: Bool, limit: Int) throws -> [Session]
    func fetchLogs(sessionID: UUID, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry]
    func tailLogs(sessionID: UUID, afterID: Int) throws -> [LogEntry]
    func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry?
    func searchLogs(query: String, sessionID: UUID?, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry]
    func latestSessionID() throws -> UUID?
}
