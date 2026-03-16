import Foundation
import AgentLogsCore

final class SessionManager: Sendable {
    private let store: SQLiteStore
    private let _sessionID: UUID

    var sessionID: UUID { _sessionID }

    init(store: SQLiteStore) throws {
        self.store = store
        let session = SessionManager.createSession()
        self._sessionID = session.id
        try store.insertSession(session)
        installCrashHandler()
    }

    func endSession() {
        try? store.endSession(id: sessionID, endedAt: Date())
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
        return String(decoding: model.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
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

    private static let crashLock = NSLock()
    private static nonisolated(unsafe) var _activeStore: SQLiteStore?
    private static nonisolated(unsafe) var _activeSessionID: UUID?

    private static func setActiveCrashState(store: SQLiteStore, sessionID: UUID) {
        crashLock.lock()
        defer { crashLock.unlock() }
        _activeStore = store
        _activeSessionID = sessionID
    }

    private static func getActiveCrashState() -> (SQLiteStore, UUID)? {
        crashLock.lock()
        defer { crashLock.unlock() }
        guard let store = _activeStore, let sid = _activeSessionID else { return nil }
        return (store, sid)
    }

    private func installCrashHandler() {
        SessionManager.setActiveCrashState(store: store, sessionID: _sessionID)
        NSSetUncaughtExceptionHandler { _ in
            guard let (store, sid) = SessionManager.getActiveCrashState() else { return }
            try? store.markSessionCrashed(id: sid)
        }
    }
}
