import Foundation

public struct Session: Identifiable, Sendable, Codable {
    public let id: UUID
    public var appName: String
    public var appVersion: String?
    public var bundleID: String?
    public var osName: String
    public var osVersion: String
    public var deviceModel: String
    public var startedAt: Date
    public var endedAt: Date?
    public var isCrashed: Bool

    public init(
        id: UUID = UUID(),
        appName: String,
        appVersion: String? = nil,
        bundleID: String? = nil,
        osName: String,
        osVersion: String,
        deviceModel: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        isCrashed: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.appVersion = appVersion
        self.bundleID = bundleID
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isCrashed = isCrashed
    }
}
