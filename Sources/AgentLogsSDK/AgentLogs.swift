import Foundation
import GRDB
import AgentLogsCore

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
        var dbQueue: DatabaseQueue?
        var sessionManager: SessionManager?
        var logBuffer: LogBuffer?
        var httpCollector: HTTPCollector?
        var systemLogCollector: SystemLogCollector?
        var osLogCollector: OSLogCollector?
        var bonjourServer: BonjourServer?
        var bonjourAdvertiser: BonjourAdvertiser?
        var configuration: Configuration?
        var isRunning = false

        func setRunning(
            dbQueue: DatabaseQueue,
            sessionManager: SessionManager,
            logBuffer: LogBuffer,
            httpCollector: HTTPCollector?,
            systemLogCollector: SystemLogCollector?,
            osLogCollector: OSLogCollector?,
            bonjourServer: BonjourServer?,
            bonjourAdvertiser: BonjourAdvertiser?,
            configuration: Configuration
        ) {
            self.dbQueue = dbQueue
            self.sessionManager = sessionManager
            self.logBuffer = logBuffer
            self.httpCollector = httpCollector
            self.systemLogCollector = systemLogCollector
            self.osLogCollector = osLogCollector
            self.bonjourServer = bonjourServer
            self.bonjourAdvertiser = bonjourAdvertiser
            self.configuration = configuration
            self.isRunning = true
        }

        func teardown() -> (
            sessionManager: SessionManager?,
            logBuffer: LogBuffer?,
            httpCollector: HTTPCollector?,
            systemLogCollector: SystemLogCollector?,
            osLogCollector: OSLogCollector?,
            bonjourServer: BonjourServer?,
            bonjourAdvertiser: BonjourAdvertiser?
        ) {
            let result = (
                sessionManager: sessionManager,
                logBuffer: logBuffer,
                httpCollector: httpCollector,
                systemLogCollector: systemLogCollector,
                osLogCollector: osLogCollector,
                bonjourServer: bonjourServer,
                bonjourAdvertiser: bonjourAdvertiser
            )
            self.dbQueue = nil
            self.sessionManager = nil
            self.logBuffer = nil
            self.httpCollector = nil
            self.systemLogCollector = nil
            self.osLogCollector = nil
            self.bonjourServer = nil
            self.bonjourAdvertiser = nil
            self.configuration = nil
            self.isRunning = false
            return result
        }

        func appendLog(_ entry: PendingLogEntry) async {
            await logBuffer?.append(entry)
        }

        func shouldLog(level: LogLevel) -> Bool {
            guard isRunning, let config = configuration else { return false }
            return logLevelOrder(level) >= logLevelOrder(config.logLevel)
        }

        func currentSessionID() -> UUID? {
            sessionManager?.sessionID
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

    /// Start the AgentLogs SDK with the given configuration.
    /// Opens the database, creates a session, and starts all enabled collectors.
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
            // Open database
            let dbPath = config.databasePath ?? DatabasePath.defaultPath()
            let dbQueue = try DatabaseSetup.openDatabase(at: dbPath)

            // Create session
            let sessionManager = try SessionManager(dbQueue: dbQueue)
            let sessionID = sessionManager.sessionID

            // Create log buffer
            let logBuffer = LogBuffer(dbQueue: dbQueue)

            // HTTP collector
            var httpCollector: HTTPCollector?
            if config.enableHTTPCapture {
                let collector = HTTPCollector(buffer: logBuffer, sessionID: sessionID)
                collector.start()
                httpCollector = collector
            }

            // System log collector (stdout/stderr)
            var systemLogCollector: SystemLogCollector?
            #if canImport(Darwin)
            if config.enableSystemLogCapture {
                let collector = SystemLogCollector(buffer: logBuffer, sessionID: sessionID)
                collector.start()
                systemLogCollector = collector
            }
            #endif

            // OSLog collector
            var osLogCollector: OSLogCollector?
            if config.enableOSLogCapture {
                let collector = OSLogCollector(buffer: logBuffer, sessionID: sessionID)
                collector.start()
                osLogCollector = collector
            }

            // Bonjour server — only on physical devices
            var bonjourServer: BonjourServer?
            var bonjourAdvertiser: BonjourAdvertiser?
            #if !targetEnvironment(simulator)
            do {
                let server = BonjourServer(dbQueue: dbQueue)
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
                dbQueue: dbQueue,
                sessionManager: sessionManager,
                logBuffer: logBuffer,
                httpCollector: httpCollector,
                systemLogCollector: systemLogCollector,
                osLogCollector: osLogCollector,
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

        let sourceFile = (file as NSString).lastPathComponent
        let entry = PendingLogEntry(
            sessionID: sessionID,
            timestamp: Date(),
            category: .custom,
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

        // Stop collectors
        components.httpCollector?.stop()
        components.systemLogCollector?.stop()
        components.osLogCollector?.stop()

        // Stop server
        components.bonjourAdvertiser?.stop()
        components.bonjourServer?.stop()

        // End session
        components.sessionManager?.endSession()
    }
}
