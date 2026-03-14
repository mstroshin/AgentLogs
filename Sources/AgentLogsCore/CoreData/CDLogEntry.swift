import Foundation
import CoreData

@objc(CDLogEntry)
public class CDLogEntry: NSManagedObject {
    @NSManaged public var sequenceID: Int64
    @NSManaged public var timestamp: Date
    @NSManaged public var category: String
    @NSManaged public var level: String
    @NSManaged public var message: String
    @NSManaged public var metadata: String?
    @NSManaged public var sourceFile: String?
    @NSManaged public var sourceLine: Int32
    @NSManaged public var session: CDSession?
    @NSManaged public var httpEntry: CDHTTPEntry?

    /// Whether sourceLine was explicitly set (CoreData stores 0 for nil Int32).
    private var hasSourceLine: Bool {
        sourceLine != 0 || sourceFile != nil
    }

    public func toLogEntry() -> LogEntry {
        LogEntry(
            id: Int(sequenceID),
            sessionID: session?.id ?? UUID(),
            timestamp: timestamp,
            category: LogCategory(rawValue: category),
            level: LogLevel(rawValue: level) ?? .info,
            message: message,
            metadata: metadata,
            sourceFile: sourceFile,
            sourceLine: hasSourceLine ? Int(sourceLine) : nil
        )
    }
}
