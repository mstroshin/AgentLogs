import Foundation
import CoreData

@objc(CDHTTPEntry)
public class CDHTTPEntry: NSManagedObject {
    @NSManaged public var method: String
    @NSManaged public var url: String
    @NSManaged public var requestHeaders: String?
    @NSManaged public var requestBody: String?
    @NSManaged public var statusCode: Int32
    @NSManaged public var responseHeaders: String?
    @NSManaged public var responseBody: String?
    @NSManaged public var durationMs: Double
    @NSManaged public var logEntry: CDLogEntry?

    /// Whether statusCode was explicitly set (0 means not set for HTTP).
    private var hasStatusCode: Bool {
        statusCode != 0
    }

    public func toHTTPEntry() -> HTTPEntry {
        HTTPEntry(
            logEntryID: Int(logEntry?.sequenceID ?? 0),
            method: method,
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            statusCode: hasStatusCode ? Int(statusCode) : nil,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            durationMs: durationMs > 0 ? durationMs : nil
        )
    }
}
