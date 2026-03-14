import Foundation
import AgentLogsCore

public struct Configuration: Sendable {
    public var collectors: [any LogCollector]
    public var logLevel: LogLevel
    public var databasePath: String?

    public init(
        collectors: [any LogCollector]? = nil,
        logLevel: LogLevel = .debug,
        databasePath: String? = nil
    ) {
        self.collectors = collectors ?? Self.defaultCollectors()
        self.logLevel = logLevel
        self.databasePath = databasePath
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
