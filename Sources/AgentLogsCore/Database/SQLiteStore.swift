import Foundation
import SQLite3

public final class SQLiteStore: @unchecked Sendable {
    private let db: OpaquePointer
    private let lock = NSLock()

    public init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let db { sqlite3_close(db) }
            throw SQLiteStoreError.openFailed(msg)
        }
        self.db = db
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try createTables()
    }

    /// In-memory store for testing.
    public convenience init() throws {
        try self.init(path: ":memory:")
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTables() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                appName TEXT NOT NULL,
                appVersion TEXT,
                bundleID TEXT,
                osName TEXT NOT NULL,
                osVersion TEXT NOT NULL,
                deviceModel TEXT NOT NULL,
                startedAt REAL NOT NULL,
                endedAt REAL,
                isCrashed INTEGER NOT NULL DEFAULT 0
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS log_entries (
                sequenceID INTEGER PRIMARY KEY AUTOINCREMENT,
                sessionID TEXT NOT NULL REFERENCES sessions(id),
                timestamp REAL NOT NULL,
                category TEXT NOT NULL,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                metadata TEXT,
                sourceFile TEXT,
                sourceLine INTEGER
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS http_entries (
                logEntryID INTEGER PRIMARY KEY REFERENCES log_entries(sequenceID),
                method TEXT NOT NULL,
                url TEXT NOT NULL,
                requestHeaders TEXT,
                requestBody TEXT,
                statusCode INTEGER,
                responseHeaders TEXT,
                responseBody TEXT,
                durationMs REAL
            )
            """)

        try execute("CREATE INDEX IF NOT EXISTS idx_log_session ON log_entries(sessionID)")
        try execute("CREATE INDEX IF NOT EXISTS idx_log_session_seq ON log_entries(sessionID, sequenceID)")
        try execute("CREATE INDEX IF NOT EXISTS idx_log_category ON log_entries(category)")
        try execute("CREATE INDEX IF NOT EXISTS idx_log_level ON log_entries(level)")
        try execute("CREATE INDEX IF NOT EXISTS idx_log_timestamp ON log_entries(timestamp)")
    }

    // MARK: - Write: Sessions

    public func insertSession(_ session: Session) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
            INSERT INTO sessions (id, appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, session.id.uuidString)
        bind(stmt, 2, session.appName)
        bind(stmt, 3, session.appVersion)
        bind(stmt, 4, session.bundleID)
        bind(stmt, 5, session.osName)
        bind(stmt, 6, session.osVersion)
        bind(stmt, 7, session.deviceModel)
        bind(stmt, 8, session.startedAt.timeIntervalSinceReferenceDate)
        bind(stmt, 9, session.endedAt?.timeIntervalSinceReferenceDate)
        bind(stmt, 10, session.isCrashed ? 1 : 0)

        try step(stmt)
    }

    public func endSession(id: UUID, endedAt: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        let stmt = try prepare("UPDATE sessions SET endedAt = ? WHERE id = ?")
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, endedAt.timeIntervalSinceReferenceDate)
        bind(stmt, 2, id.uuidString)
        try step(stmt)
    }

    public func markSessionCrashed(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let stmt = try prepare("UPDATE sessions SET isCrashed = 1, endedAt = ? WHERE id = ?")
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, Date().timeIntervalSinceReferenceDate)
        bind(stmt, 2, id.uuidString)
        try step(stmt)
    }

    // MARK: - Write: Log Entries (batch)

    public struct PendingLog: Sendable {
        public var sessionID: UUID
        public var timestamp: Date
        public var category: LogCategory
        public var level: LogLevel
        public var message: String
        public var metadata: String?
        public var sourceFile: String?
        public var sourceLine: Int?
        public var http: PendingHTTP?

        public init(
            sessionID: UUID,
            timestamp: Date,
            category: LogCategory,
            level: LogLevel,
            message: String,
            metadata: String? = nil,
            sourceFile: String? = nil,
            sourceLine: Int? = nil,
            http: PendingHTTP? = nil
        ) {
            self.sessionID = sessionID
            self.timestamp = timestamp
            self.category = category
            self.level = level
            self.message = message
            self.metadata = metadata
            self.sourceFile = sourceFile
            self.sourceLine = sourceLine
            self.http = http
        }
    }

    public struct PendingHTTP: Sendable {
        public var method: String
        public var url: String
        public var requestHeaders: String?
        public var requestBody: String?
        public var statusCode: Int?
        public var responseHeaders: String?
        public var responseBody: String?
        public var durationMs: Double?

        public init(
            method: String,
            url: String,
            requestHeaders: String? = nil,
            requestBody: String? = nil,
            statusCode: Int? = nil,
            responseHeaders: String? = nil,
            responseBody: String? = nil,
            durationMs: Double? = nil
        ) {
            self.method = method
            self.url = url
            self.requestHeaders = requestHeaders
            self.requestBody = requestBody
            self.statusCode = statusCode
            self.responseHeaders = responseHeaders
            self.responseBody = responseBody
            self.durationMs = durationMs
        }
    }

    @discardableResult
    public func insertLogEntries(_ entries: [PendingLog]) throws -> [Int64] {
        guard !entries.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        try executeUnlocked("BEGIN TRANSACTION")

        var sequenceIDs: [Int64] = []
        sequenceIDs.reserveCapacity(entries.count)

        do {
            let logSQL = """
                INSERT INTO log_entries (sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """
            let logStmt = try prepare(logSQL)
            defer { sqlite3_finalize(logStmt) }

            let httpSQL = """
                INSERT INTO http_entries (logEntryID, method, url, requestHeaders, requestBody, statusCode, responseHeaders, responseBody, durationMs)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            let httpStmt = try prepare(httpSQL)
            defer { sqlite3_finalize(httpStmt) }

            for entry in entries {
                sqlite3_reset(logStmt)
                sqlite3_clear_bindings(logStmt)

                bind(logStmt, 1, entry.sessionID.uuidString)
                bind(logStmt, 2, entry.timestamp.timeIntervalSinceReferenceDate)
                bind(logStmt, 3, entry.category.rawValue)
                bind(logStmt, 4, entry.level.rawValue)
                bind(logStmt, 5, entry.message)
                bind(logStmt, 6, entry.metadata)
                bind(logStmt, 7, entry.sourceFile)
                bind(logStmt, 8, entry.sourceLine)

                try step(logStmt)

                let seqID = sqlite3_last_insert_rowid(db)
                sequenceIDs.append(seqID)

                if let http = entry.http {
                    sqlite3_reset(httpStmt)
                    sqlite3_clear_bindings(httpStmt)

                    bind(httpStmt, 1, seqID)
                    bind(httpStmt, 2, http.method)
                    bind(httpStmt, 3, http.url)
                    bind(httpStmt, 4, http.requestHeaders)
                    bind(httpStmt, 5, http.requestBody)
                    bind(httpStmt, 6, http.statusCode)
                    bind(httpStmt, 7, http.responseHeaders)
                    bind(httpStmt, 8, http.responseBody)
                    bind(httpStmt, 9, http.durationMs)

                    try step(httpStmt)
                }
            }

            try executeUnlocked("COMMIT")
        } catch {
            try? executeUnlocked("ROLLBACK")
            throw error
        }

        return sequenceIDs
    }

    // MARK: - Read: Sessions

    public func fetchSessions(
        crashedOnly: Bool = false,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [Session] {
        lock.lock()
        defer { lock.unlock() }

        var sql = "SELECT id, appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed FROM sessions"
        if crashedOnly {
            sql += " WHERE isCrashed = 1"
        }
        sql += " ORDER BY startedAt DESC LIMIT ? OFFSET ?"

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, limit)
        bind(stmt, 2, offset)

        var sessions: [Session] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sessions.append(readSession(stmt))
        }
        return sessions
    }

    // MARK: - Read: Logs

    public func fetchLogs(
        sessionID: UUID,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        sinceTimestamp: Date? = nil,
        limit: Int = 500
    ) throws -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        var sql = "SELECT sequenceID, sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine FROM log_entries WHERE sessionID = ?"
        var params: [Any] = [sessionID.uuidString]

        if let category {
            sql += " AND category = ?"
            params.append(category.rawValue)
        }
        if let level {
            sql += " AND level = ?"
            params.append(level.rawValue)
        }
        if let sinceTimestamp {
            sql += " AND timestamp > ?"
            params.append(sinceTimestamp.timeIntervalSinceReferenceDate)
        }
        sql += " ORDER BY timestamp ASC LIMIT ?"
        params.append(limit)

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            bindAny(stmt, Int32(i + 1), param)
        }

        var entries: [LogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(readLogEntry(stmt))
        }
        return entries
    }

    public func tailLogs(
        sessionID: UUID,
        afterID: Int
    ) throws -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
            SELECT sequenceID, sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine
            FROM log_entries WHERE sessionID = ? AND sequenceID > ?
            ORDER BY sequenceID ASC
            """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, sessionID.uuidString)
        bind(stmt, 2, Int64(afterID))

        var entries: [LogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(readLogEntry(stmt))
        }
        return entries
    }

    public func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT logEntryID, method, url, requestHeaders, requestBody, statusCode, responseHeaders, responseBody, durationMs FROM http_entries WHERE logEntryID = ?"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, Int64(logEntryID))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readHTTPEntry(stmt)
    }

    public func searchLogs(
        query: String,
        sessionID: UUID? = nil,
        category: LogCategory? = nil,
        level: LogLevel? = nil,
        limit: Int = 100
    ) throws -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        var sql = "SELECT sequenceID, sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine FROM log_entries WHERE message LIKE ?"
        var params: [Any] = ["%\(query)%"]

        if let sessionID {
            sql += " AND sessionID = ?"
            params.append(sessionID.uuidString)
        }
        if let category {
            sql += " AND category = ?"
            params.append(category.rawValue)
        }
        if let level {
            sql += " AND level = ?"
            params.append(level.rawValue)
        }
        sql += " ORDER BY timestamp DESC LIMIT ?"
        params.append(limit)

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            bindAny(stmt, Int32(i + 1), param)
        }

        var entries: [LogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(readLogEntry(stmt))
        }
        return entries
    }

    public func latestSessionID() throws -> UUID? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id FROM sessions ORDER BY startedAt DESC LIMIT 1"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readString(stmt, 0).flatMap(UUID.init)
    }

    public func fetchErrors(
        sessionID: UUID,
        limit: Int = 100
    ) throws -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
            SELECT sequenceID, sessionID, timestamp, category, level, message, metadata, sourceFile, sourceLine
            FROM log_entries WHERE sessionID = ? AND level IN (?, ?)
            ORDER BY timestamp DESC LIMIT ?
            """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, sessionID.uuidString)
        bind(stmt, 2, LogLevel.error.rawValue)
        bind(stmt, 3, LogLevel.critical.rawValue)
        bind(stmt, 4, limit)

        var entries: [LogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(readLogEntry(stmt))
        }
        return entries
    }

    public func maxSequenceID() throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT MAX(sequenceID) FROM log_entries"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        let val = sqlite3_column_int64(stmt, 0)
        return val
    }

    // MARK: - Row Readers

    private func readSession(_ stmt: OpaquePointer) -> Session {
        Session(
            id: UUID(uuidString: readString(stmt, 0) ?? "") ?? UUID(),
            appName: readString(stmt, 1) ?? "",
            appVersion: readString(stmt, 2),
            bundleID: readString(stmt, 3),
            osName: readString(stmt, 4) ?? "",
            osVersion: readString(stmt, 5) ?? "",
            deviceModel: readString(stmt, 6) ?? "",
            startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 7)),
            endedAt: sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 8))
                : nil,
            isCrashed: sqlite3_column_int(stmt, 9) != 0
        )
    }

    private func readLogEntry(_ stmt: OpaquePointer) -> LogEntry {
        let sourceLine: Int? = sqlite3_column_type(stmt, 8) != SQLITE_NULL
            ? Int(sqlite3_column_int(stmt, 8))
            : nil

        return LogEntry(
            id: Int(sqlite3_column_int64(stmt, 0)),
            sessionID: UUID(uuidString: readString(stmt, 1) ?? "") ?? UUID(),
            timestamp: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 2)),
            category: LogCategory(rawValue: readString(stmt, 3) ?? ""),
            level: LogLevel(rawValue: readString(stmt, 4) ?? "") ?? .info,
            message: readString(stmt, 5) ?? "",
            metadata: readString(stmt, 6),
            sourceFile: readString(stmt, 7),
            sourceLine: sourceLine
        )
    }

    private func readHTTPEntry(_ stmt: OpaquePointer) -> HTTPEntry {
        HTTPEntry(
            logEntryID: Int(sqlite3_column_int64(stmt, 0)),
            method: readString(stmt, 1) ?? "",
            url: readString(stmt, 2) ?? "",
            requestHeaders: readString(stmt, 3),
            requestBody: readString(stmt, 4),
            statusCode: sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 5)) : nil,
            responseHeaders: readString(stmt, 6),
            responseBody: readString(stmt, 7),
            durationMs: sqlite3_column_type(stmt, 8) != SQLITE_NULL ? sqlite3_column_double(stmt, 8) : nil
        )
    }

    // MARK: - SQLite Helpers

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked(sql)
    }

    private func executeUnlocked(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if rc != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errmsg)
            throw SQLiteStoreError.execFailed(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func step(_ stmt: OpaquePointer) throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func readString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    // MARK: - Bind Helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(stmt, index, Int64(value))
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bindAny(_ stmt: OpaquePointer, _ index: Int32, _ value: Any) {
        switch value {
        case let s as String:
            bind(stmt, index, s)
        case let d as Double:
            bind(stmt, index, d)
        case let i as Int:
            bind(stmt, index, i)
        case let i as Int64:
            bind(stmt, index, i)
        default:
            sqlite3_bind_null(stmt, index)
        }
    }
}

// MARK: - Errors

public enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .execFailed(let msg): return "SQLite exec failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        }
    }
}
