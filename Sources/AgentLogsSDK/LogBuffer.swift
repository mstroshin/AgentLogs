import Foundation
import AgentLogsCore

/// A pending log entry before it gets written to the database.
public struct PendingLogEntry: Sendable {
    public var sessionID: UUID
    public var timestamp: Date
    public var category: LogCategory
    public var level: LogLevel
    public var message: String
    public var metadata: String?
    public var sourceFile: String?
    public var sourceLine: Int?
    var httpEntry: PendingHTTPEntry?

    public init(
        sessionID: UUID,
        timestamp: Date,
        category: LogCategory,
        level: LogLevel,
        message: String,
        metadata: String? = nil,
        sourceFile: String? = nil,
        sourceLine: Int? = nil
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        self.httpEntry = nil
    }
}

extension PendingLogEntry {
    /// Internal initializer that includes httpEntry (used by HTTPCollector).
    init(
        sessionID: UUID,
        timestamp: Date,
        category: LogCategory,
        level: LogLevel,
        message: String,
        metadata: String? = nil,
        sourceFile: String? = nil,
        sourceLine: Int? = nil,
        httpEntry: PendingHTTPEntry?
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        self.httpEntry = httpEntry
    }
}

/// HTTP details that will be inserted after the log entry.
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

actor LogBuffer: LogSink {
    private let store: SQLiteStore
    private var buffer: [PendingLogEntry] = []
    private var flushTask: Task<Void, Never>?

    private let maxBufferSize = 50
    private let flushIntervalNanoseconds: UInt64 = 500_000_000  // 500ms

    init(store: SQLiteStore) {
        self.store = store
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

        let pendingLogs = entries.map { entry in
            SQLiteStore.PendingLog(
                sessionID: entry.sessionID,
                timestamp: entry.timestamp,
                category: entry.category,
                level: entry.level,
                message: entry.message,
                metadata: entry.metadata,
                sourceFile: entry.sourceFile,
                sourceLine: entry.sourceLine,
                http: entry.httpEntry.map {
                    SQLiteStore.PendingHTTP(
                        method: $0.method,
                        url: $0.url,
                        requestHeaders: $0.requestHeaders,
                        requestBody: $0.requestBody,
                        statusCode: $0.statusCode,
                        responseHeaders: $0.responseHeaders,
                        responseBody: $0.responseBody,
                        durationMs: $0.durationMs
                    )
                }
            )
        }

        do {
            try store.insertLogEntries(pendingLogs)
        } catch {
            fputs("[AgentLogs] LogBuffer flush failed: \(error)\n", stderr)
        }
    }
}
