import Foundation
import GRDB

public struct LogEntry: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public let id: Int
    public var sessionID: UUID
    public var timestamp: Date
    public var category: LogCategory
    public var level: LogLevel
    public var message: String
    public var metadata: String?
    public var sourceFile: String?
    public var sourceLine: Int?

    public init(
        id: Int,
        sessionID: UUID,
        timestamp: Date = Date(),
        category: LogCategory,
        level: LogLevel,
        message: String,
        metadata: String? = nil,
        sourceFile: String? = nil,
        sourceLine: Int? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }

    // MARK: - PersistableRecord

    /// Encode sessionID as TEXT (uuidString) instead of GRDB's default 16-byte BLOB.
    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["sessionID"] = sessionID.uuidString
        container["timestamp"] = timestamp
        container["category"] = category
        container["level"] = level
        container["message"] = message
        container["metadata"] = metadata
        container["sourceFile"] = sourceFile
        container["sourceLine"] = sourceLine
    }

    // MARK: - FetchableRecord

    /// Decode sessionID from TEXT (uuidString) stored in the database.
    public init(row: Row) throws {
        let sessionIDString: String = row["sessionID"]
        guard let uuid = UUID(uuidString: sessionIDString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid UUID string '\(sessionIDString)' in logEntry.sessionID"
                )
            )
        }
        id = row["id"]
        sessionID = uuid
        timestamp = row["timestamp"]
        category = row["category"]
        level = row["level"]
        message = row["message"]
        metadata = row["metadata"]
        sourceFile = row["sourceFile"]
        sourceLine = row["sourceLine"]
    }
}
