import Foundation
import GRDB
import AgentLogsCore

final class SessionManager: Sendable {
    private let dbQueue: DatabaseQueue
    private let _sessionID: UUID

    var sessionID: UUID { _sessionID }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        let session = SessionManager.createSession()
        self._sessionID = session.id
        try dbQueue.write { db in
            try session.insert(db)
        }
        installCrashHandler()
    }

    func endSession() {
        do {
            try dbQueue.write { [sessionID] db in
                try db.execute(
                    sql: "UPDATE session SET endedAt = ? WHERE id = ?",
                    arguments: [Date(), sessionID.uuidString]
                )
            }
        } catch {
            // Best effort — session end is non-critical
        }
    }

    private static func createSession() -> Session {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let bundleID = Bundle.main.bundleIdentifier

        let osName: String
        let osVersion: String
        let deviceModel: String

        #if os(iOS) || os(tvOS) || os(watchOS)
        #if canImport(UIKit)
        osName = "iOS"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        deviceModel = Self.iosDeviceModel()
        #else
        osName = "iOS"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        deviceModel = "Unknown"
        #endif
        #elseif os(macOS)
        osName = "macOS"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        deviceModel = Self.macDeviceModel()
        #else
        osName = "Unknown"
        osVersion = "Unknown"
        deviceModel = "Unknown"
        #endif

        return Session(
            appName: appName,
            appVersion: appVersion,
            bundleID: bundleID,
            osName: osName,
            osVersion: osVersion,
            deviceModel: deviceModel
        )
    }

    #if os(macOS)
    private static func macDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    #endif

    #if os(iOS) || os(tvOS) || os(watchOS)
    private static func iosDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
    }
    #endif

    // MARK: - Crash Handler

    /// Stored reference so the handler closure can access the DB path.
    /// Protected by a lock for thread-safe access.
    private static let crashLock = NSLock()
    private static nonisolated(unsafe) var _activeDBQueue: DatabaseQueue?
    private static nonisolated(unsafe) var _activeSessionID: UUID?

    private static func setActiveCrashState(dbQueue: DatabaseQueue, sessionID: UUID) {
        crashLock.lock()
        defer { crashLock.unlock() }
        _activeDBQueue = dbQueue
        _activeSessionID = sessionID
    }

    private static func getActiveCrashState() -> (DatabaseQueue, UUID)? {
        crashLock.lock()
        defer { crashLock.unlock() }
        guard let db = _activeDBQueue, let sid = _activeSessionID else { return nil }
        return (db, sid)
    }

    private func installCrashHandler() {
        SessionManager.setActiveCrashState(dbQueue: dbQueue, sessionID: _sessionID)
        NSSetUncaughtExceptionHandler { _ in
            guard let (database, sid) = SessionManager.getActiveCrashState() else { return }
            try? database.write { db in
                try db.execute(
                    sql: "UPDATE session SET isCrashed = 1, endedAt = ? WHERE id = ?",
                    arguments: [Date(), sid.uuidString]
                )
            }
        }
    }
}
