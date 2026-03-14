import Foundation
import CoreData
import AgentLogsCore

/// A pending log entry before it gets written to CoreData.
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
    private let context: NSManagedObjectContext
    private var buffer: [PendingLogEntry] = []
    private var flushTask: Task<Void, Never>?
    private var nextSequenceID: Int64 = 1

    private let maxBufferSize = 50
    private let flushIntervalNanoseconds: UInt64 = 500_000_000  // 500ms

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Set the starting sequence ID (e.g., after loading max from store).
    func setNextSequenceID(_ id: Int64) {
        self.nextSequenceID = id
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

        let context = self.context
        var seqID = self.nextSequenceID

        context.performAndWait {
            // Fetch the CDSession objects needed (cache by sessionID)
            var sessionCache: [UUID: CDSession] = [:]

            for entry in entries {
                let cdSession: CDSession? = {
                    if let cached = sessionCache[entry.sessionID] {
                        return cached
                    }
                    let request = NSFetchRequest<CDSession>(entityName: "CDSession")
                    request.predicate = NSPredicate(format: "id == %@", entry.sessionID as CVarArg)
                    request.fetchLimit = 1
                    let result = try? context.fetch(request).first
                    if let result {
                        sessionCache[entry.sessionID] = result
                    }
                    return result
                }()

                let cdEntry = CDLogEntry(context: context)
                cdEntry.sequenceID = seqID
                seqID += 1
                cdEntry.timestamp = entry.timestamp
                cdEntry.category = entry.category.rawValue
                cdEntry.level = entry.level.rawValue
                cdEntry.message = entry.message
                cdEntry.metadata = entry.metadata
                cdEntry.sourceFile = entry.sourceFile
                cdEntry.sourceLine = Int32(entry.sourceLine ?? 0)
                cdEntry.session = cdSession

                if let http = entry.httpEntry {
                    let cdHTTP = CDHTTPEntry(context: context)
                    cdHTTP.method = http.method
                    cdHTTP.url = http.url
                    cdHTTP.requestHeaders = http.requestHeaders
                    cdHTTP.requestBody = http.requestBody
                    cdHTTP.statusCode = Int32(http.statusCode ?? 0)
                    cdHTTP.responseHeaders = http.responseHeaders
                    cdHTTP.responseBody = http.responseBody
                    cdHTTP.durationMs = http.durationMs ?? 0
                    cdHTTP.logEntry = cdEntry
                }
            }

            do {
                try context.save()
            } catch {
                fputs("[AgentLogs] LogBuffer flush failed: \(error)\n", stderr)
            }
        }

        self.nextSequenceID = seqID
    }
}
