import Foundation
import CoreData

@objc(CDSession)
public class CDSession: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var appName: String
    @NSManaged public var appVersion: String?
    @NSManaged public var bundleID: String?
    @NSManaged public var osName: String
    @NSManaged public var osVersion: String
    @NSManaged public var deviceModel: String
    @NSManaged public var startedAt: Date
    @NSManaged public var endedAt: Date?
    @NSManaged public var isCrashed: Bool
    @NSManaged public var logEntries: NSSet?

    public func toSession() -> Session {
        Session(
            id: id,
            appName: appName,
            appVersion: appVersion,
            bundleID: bundleID,
            osName: osName,
            osVersion: osVersion,
            deviceModel: deviceModel,
            startedAt: startedAt,
            endedAt: endedAt,
            isCrashed: isCrashed
        )
    }

    public func populate(from session: Session) {
        self.id = session.id
        self.appName = session.appName
        self.appVersion = session.appVersion
        self.bundleID = session.bundleID
        self.osName = session.osName
        self.osVersion = session.osVersion
        self.deviceModel = session.deviceModel
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.isCrashed = session.isCrashed
    }
}
