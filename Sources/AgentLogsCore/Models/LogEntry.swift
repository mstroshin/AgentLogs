import Foundation

public struct LogEntry: Identifiable, Sendable, Codable {
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
}
