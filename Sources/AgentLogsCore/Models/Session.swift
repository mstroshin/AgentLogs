import Foundation
import GRDB

public struct Session: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
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

    // MARK: - PersistableRecord

    /// Encode UUID as TEXT (uuidString) instead of GRDB's default 16-byte BLOB.
    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["appName"] = appName
        container["appVersion"] = appVersion
        container["bundleID"] = bundleID
        container["osName"] = osName
        container["osVersion"] = osVersion
        container["deviceModel"] = deviceModel
        container["startedAt"] = startedAt
        container["endedAt"] = endedAt
        container["isCrashed"] = isCrashed
    }

    // MARK: - FetchableRecord

    /// Decode UUID from TEXT (uuidString) stored in the database.
    public init(row: Row) throws {
        let idString: String = row["id"]
        guard let uuid = UUID(uuidString: idString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid UUID string '\(idString)' in session.id"
                )
            )
        }
        id = uuid
        appName = row["appName"]
        appVersion = row["appVersion"]
        bundleID = row["bundleID"]
        osName = row["osName"]
        osVersion = row["osVersion"]
        deviceModel = row["deviceModel"]
        startedAt = row["startedAt"]
        endedAt = row["endedAt"]
        isCrashed = row["isCrashed"]
    }
}
