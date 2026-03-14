import Foundation

public struct HTTPEntry: Identifiable, Sendable, Codable {
    public let logEntryID: Int
    public var method: String
    public var url: String
    public var requestHeaders: String?
    public var requestBody: String?
    public var statusCode: Int?
    public var responseHeaders: String?
    public var responseBody: String?
    public var durationMs: Double?

    public var id: Int { logEntryID }

    public init(
        logEntryID: Int,
        method: String,
        url: String,
        requestHeaders: String? = nil,
        requestBody: String? = nil,
        statusCode: Int? = nil,
        responseHeaders: String? = nil,
        responseBody: String? = nil,
        durationMs: Double? = nil
    ) {
        self.logEntryID = logEntryID
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
