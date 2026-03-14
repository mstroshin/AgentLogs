import Foundation
import GRDB
import AgentLogsCore

/// A pending log entry before it gets an autoincremented ID from the database.
struct PendingLogEntry: Sendable {
    var sessionID: UUID
    var timestamp: Date
    var category: LogCategory
    var level: LogLevel
    var message: String
    var metadata: String?
    var sourceFile: String?
    var sourceLine: Int?
    var httpEntry: PendingHTTPEntry?
}

/// HTTP details that will be inserted after the log entry gets its ID.
struct PendingHTTPEntry: Sendable {
    var method: String
    var url: String
    var requestHeaders: String?
    var requestBody: String?
    var statusCode: Int?
    var responseHeaders: String?
    var responseBody: String?
    var durationMs: Double?
}

actor LogBuffer {
    private let dbQueue: DatabaseQueue
    private var buffer: [PendingLogEntry] = []
    private var flushTask: Task<Void, Never>?

    private let maxBufferSize = 50
    private let flushIntervalNanoseconds: UInt64 = 500_000_000  // 500ms

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func append(_ entry: PendingLogEntry) {
        buffer.append(entry)
        if buffer.count >= maxBufferSize {
            performFlush()
        } else if flushTask == nil {
            scheduleFlush()
        }
    }

    func flush() {
        performFlush()
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
        performFlush()
    }

    private func scheduleFlush() {
        flushTask = Task { [weak self, flushIntervalNanoseconds] in
            try? await Task.sleep(nanoseconds: flushIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performFlush()
        }
    }

    private func performFlush() {
        flushTask?.cancel()
        flushTask = nil

        guard !buffer.isEmpty else { return }
        let entries = buffer
        buffer = []

        do {
            try dbQueue.write { database in
                for entry in entries {
                    // Insert the log entry using raw SQL so we get the autoincremented ID
                    try database.execute(
                        sql: """
                            INSERT INTO logEntry (sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            entry.sessionID.uuidString,
                            entry.timestamp.timeIntervalSinceReferenceDate,
                            entry.category.rawValue,
                            entry.level.rawValue,
                            entry.message,
                            entry.metadata,
                            entry.sourceFile,
                            entry.sourceLine,
                        ]
                    )

                    if let http = entry.httpEntry {
                        let logEntryID = database.lastInsertedRowID
                        try database.execute(
                            sql: """
                                INSERT INTO httpEntry (logEntryID, method, url, requestHeaders, requestBody, statusCode, responseHeaders, responseBody, durationMs)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                                """,
                            arguments: [
                                logEntryID,
                                http.method,
                                http.url,
                                http.requestHeaders,
                                http.requestBody,
                                http.statusCode,
                                http.responseHeaders,
                                http.responseBody,
                                http.durationMs,
                            ]
                        )
                    }
                }
            }
        } catch {
            // Logging framework should not crash the host app, but report to stderr
            fputs("[AgentLogs] LogBuffer flush failed: \(error)\n", stderr)
        }
    }
}
