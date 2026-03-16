import Foundation
import CoreData
import AgentLogsCore
#if canImport(OSLog)
import OSLog
#endif

/// Main public API for the AgentLogs SDK.
///
/// Usage:
/// ```swift
/// AgentLogs.start()
/// AgentLogs.log("Something happened")
/// AgentLogs.log("Bad thing", type: .error)
/// AgentLogs.stop()
/// ```
public final class AgentLogs: Sendable {

    // MARK: - Singleton state

    /// All mutable state is protected by this actor.
    private actor State {
        var container: NSPersistentContainer?
        var sessionManager: SessionManager?
        var logBuffer: LogBuffer?
        var collectors: [any LogCollector] = []
        var bonjourServer: BonjourServer?
        var bonjourAdvertiser: BonjourAdvertiser?
        var configuration: Configuration?
        #if canImport(OSLog)
        var osLogWriter: OSLogWriter?
        #endif
        var isRunning = false

        func setRunning(
            container: NSPersistentContainer,
            sessionManager: SessionManager,
            logBuffer: LogBuffer,
            collectors: [any LogCollector],
            bonjourServer: BonjourServer?,
            bonjourAdvertiser: BonjourAdvertiser?,
            configuration: Configuration
        ) {
            self.container = container
            self.sessionManager = sessionManager
            self.logBuffer = logBuffer
            self.collectors = collectors
            self.bonjourServer = bonjourServer
            self.bonjourAdvertiser = bonjourAdvertiser
            self.configuration = configuration
            #if canImport(OSLog)
            if configuration.osLog.enabled {
                let subsystem = configuration.osLog.subsystem
                    ?? (Bundle.main.bundleIdentifier.map { "\($0).agentlogs" }
                        ?? "com.agentlogs.output")
                self.osLogWriter = OSLogWriter(
                    subsystem: subsystem,
                    category: configuration.osLog.category
                )
            }
            #endif
            self.isRunning = true
        }

        func teardown() -> (
            sessionManager: SessionManager?,
            logBuffer: LogBuffer?,
            collectors: [any LogCollector],
            bonjourServer: BonjourServer?,
            bonjourAdvertiser: BonjourAdvertiser?
        ) {
            let result = (
                sessionManager: sessionManager,
                logBuffer: logBuffer,
                collectors: collectors,
                bonjourServer: bonjourServer,
                bonjourAdvertiser: bonjourAdvertiser
            )
            self.container = nil
            self.sessionManager = nil
            self.logBuffer = nil
            self.collectors = []
            self.bonjourServer = nil
            self.bonjourAdvertiser = nil
            self.configuration = nil
            #if canImport(OSLog)
            self.osLogWriter = nil
            #endif
            self.isRunning = false
            return result
        }

        func appendLog(_ entry: PendingLogEntry) async {
            await logBuffer?.append(entry)
        }

        #if canImport(OSLog)
        func writeToOSLog(_ message: String, level: LogLevel) {
            osLogWriter?.write(message, level: level)
        }
        #endif

        func shouldLog(level: LogLevel) -> Bool {
            guard isRunning, let config = configuration else { return false }
            return logLevelOrder(level) >= logLevelOrder(config.logLevel)
        }

        func currentSessionID() -> UUID? {
            sessionManager?.sessionID
        }

        func uiContext() -> (NSManagedObjectContext, UUID)? {
            guard isRunning, let container, let sm = sessionManager else { return nil }
            return (container.viewContext, sm.sessionID)
        }

        private func logLevelOrder(_ level: LogLevel) -> Int {
            switch level {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            case .critical: return 4
            }
        }
    }

    private static let state = State()

    private init() {}

    // MARK: - Public API

    /// Returns the CoreData view context and current session ID for UI consumption.
    /// Returns nil if the SDK is not running.
    public static func uiContext() async -> (context: NSManagedObjectContext, sessionID: UUID)? {
        await state.uiContext()
    }

    /// Start the AgentLogs SDK with the given configuration.
    public static func start(config: Configuration = Configuration()) {
        #if DEBUG || AGENTLOGS_ENABLED
        Task {
            await _start(config: config)
        }
        #endif
    }

    /// Log a message at the specified level.
    public static func log(
        _ message: String,
        type: LogLevel = .info,
        file: String = #file,
        line: Int = #line
    ) {
        #if DEBUG || AGENTLOGS_ENABLED
        Task {
            await _log(message, type: type, file: file, line: line)
        }
        #endif
    }

    /// Stop the SDK: flush the buffer, end the session, stop all collectors and servers.
    public static func stop() {
        #if DEBUG || AGENTLOGS_ENABLED
        Task {
            await _stop()
        }
        #endif
    }

    // MARK: - Internal Implementation

    private static func _start(config: Configuration) async {
        guard await !state.isRunning else { return }

        do {
            // Setup CoreData
            let storePath = config.databasePath ?? DatabasePath.defaultPath()
            let storeURL = URL(fileURLWithPath: storePath)

            // Ensure directory exists
            let directory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let container = CoreDataStack.createContainer(at: storeURL)

            // Load persistent stores synchronously
            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            // Create session
            let sessionManager = try SessionManager(container: container)
            let sessionID = sessionManager.sessionID

            // Create log buffer with background context
            let bgContext = container.newBackgroundContext()
            bgContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            let logBuffer = LogBuffer(context: bgContext)

            // Determine next sequence ID
            let maxSeqID: Int64 = try bgContext.performAndWait {
                let request = NSFetchRequest<CDLogEntry>(entityName: "CDLogEntry")
                request.sortDescriptors = [NSSortDescriptor(key: "sequenceID", ascending: false)]
                request.fetchLimit = 1
                return try bgContext.fetch(request).first?.sequenceID ?? 0
            }
            await logBuffer.setNextSequenceID(maxSeqID + 1)

            // Start all collectors
            let context = CollectorContext(sink: logBuffer, sessionID: sessionID)
            for collector in config.collectors {
                await collector.start(context: context)
            }

            // Bonjour server — only on physical devices
            var bonjourServer: BonjourServer?
            var bonjourAdvertiser: BonjourAdvertiser?
            #if !targetEnvironment(simulator)
            do {
                let server = BonjourServer(container: container)
                try server.start()
                bonjourServer = server

                let advertiser = BonjourAdvertiser(
                    port: server.port,
                    sessionID: sessionID.uuidString,
                    bundleID: Bundle.main.bundleIdentifier ?? "com.agentlogs.unknown"
                )
                advertiser.start()
                bonjourAdvertiser = advertiser
            } catch {
                // Server start failure is non-fatal
            }
            #endif

            await state.setRunning(
                container: container,
                sessionManager: sessionManager,
                logBuffer: logBuffer,
                collectors: config.collectors,
                bonjourServer: bonjourServer,
                bonjourAdvertiser: bonjourAdvertiser,
                configuration: config
            )
        } catch {
            // Database/session creation failure — SDK becomes a no-op
        }
    }

    private static func _log(
        _ message: String,
        type: LogLevel,
        file: String,
        line: Int
    ) async {
        guard await state.shouldLog(level: type) else { return }
        guard let sessionID = await state.currentSessionID() else { return }

        #if canImport(OSLog)
        await state.writeToOSLog(message, level: type)
        #endif

        let sourceFile = (file as NSString).lastPathComponent
        let entry = PendingLogEntry(
            sessionID: sessionID,
            timestamp: Date(),
            category: .manualLogs,
            level: type,
            message: message,
            sourceFile: sourceFile,
            sourceLine: line
        )
        await state.appendLog(entry)
    }

    private static func _stop() async {
        let components = await state.teardown()

        // Flush buffer
        await components.logBuffer?.stop()

        // Stop all collectors
        for collector in components.collectors {
            await collector.stop()
        }

        // Stop server
        components.bonjourAdvertiser?.stop()
        components.bonjourServer?.stop()

        // End session
        components.sessionManager?.endSession()
    }
}
