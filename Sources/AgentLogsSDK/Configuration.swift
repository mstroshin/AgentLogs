import Foundation
import AgentLogsCore

public struct Configuration: Sendable {
    public var collectors: [any LogCollector]
    public var logLevel: LogLevel
    public var databasePath: String?
    public var osLog: OSLogOutputConfig

    public init(
        collectors: [any LogCollector]? = nil,
        logLevel: LogLevel = .debug,
        databasePath: String? = nil,
        osLog: OSLogOutputConfig = OSLogOutputConfig()
    ) {
        self.collectors = collectors ?? Self.defaultCollectors()
        self.logLevel = logLevel
        self.databasePath = databasePath
        self.osLog = osLog
    }

    /// Configuration for writing logs to Apple Unified Logging (Console.app / Instruments).
    public struct OSLogOutputConfig: Sendable {
        /// Enable writing manual logs to OSLog. Defaults to `true`.
        public var enabled: Bool
        /// OSLog subsystem. Defaults to `"\(bundleID).agentlogs"` to avoid duplicates with OSLogCollector.
        public var subsystem: String?
        /// OSLog category. Defaults to `"AgentLogs"`.
        public var category: String

        public init(
            enabled: Bool = true,
            subsystem: String? = nil,
            category: String = "AgentLogs"
        ) {
            self.enabled = enabled
            self.subsystem = subsystem
            self.category = category
        }
    }

    public static func defaultCollectors() -> [any LogCollector] {
        var result: [any LogCollector] = [HTTPCollector()]
        #if canImport(Darwin)
        result.append(SystemLogCollector())
        #endif
        result.append(OSLogCollector())
        return result
    }
}
