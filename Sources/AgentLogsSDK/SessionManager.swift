import Foundation
import CoreData
import AgentLogsCore

final class SessionManager: Sendable {
    private let container: NSPersistentContainer
    private let _sessionID: UUID

    var sessionID: UUID { _sessionID }

    init(container: NSPersistentContainer) throws {
        self.container = container
        let session = SessionManager.createSession()
        self._sessionID = session.id

        let context = container.viewContext
        context.performAndWait {
            let cdSession = CDSession(context: context)
            cdSession.populate(from: session)
            try? context.save()
        }
        installCrashHandler()
    }

    func endSession() {
        let context = container.newBackgroundContext()
        let sid = sessionID
        context.performAndWait {
            let request = NSFetchRequest<CDSession>(entityName: "CDSession")
            request.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
            request.fetchLimit = 1
            if let cdSession = try? context.fetch(request).first {
                cdSession.endedAt = Date()
                try? context.save()
            }
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
    private static nonisolated(unsafe) var _activeContainer: NSPersistentContainer?
    private static nonisolated(unsafe) var _activeSessionID: UUID?

    private static func setActiveCrashState(container: NSPersistentContainer, sessionID: UUID) {
        crashLock.lock()
        defer { crashLock.unlock() }
        _activeContainer = container
        _activeSessionID = sessionID
    }

    private static func getActiveCrashState() -> (NSPersistentContainer, UUID)? {
        crashLock.lock()
        defer { crashLock.unlock() }
        guard let container = _activeContainer, let sid = _activeSessionID else { return nil }
        return (container, sid)
    }

    private func installCrashHandler() {
        SessionManager.setActiveCrashState(container: container, sessionID: _sessionID)
        NSSetUncaughtExceptionHandler { _ in
            guard let (container, sid) = SessionManager.getActiveCrashState() else { return }
            let context = container.newBackgroundContext()
            context.performAndWait {
                let request = NSFetchRequest<CDSession>(entityName: "CDSession")
                request.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
                request.fetchLimit = 1
                if let cdSession = try? context.fetch(request).first {
                    cdSession.isCrashed = true
                    cdSession.endedAt = Date()
                    try? context.save()
                }
            }
        }
    }
}
