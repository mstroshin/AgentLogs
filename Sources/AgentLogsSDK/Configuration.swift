import Foundation
import AgentLogsCore

public struct Configuration: Sendable {
    public var enableHTTPCapture: Bool
    public var enableSystemLogCapture: Bool
    public var enableOSLogCapture: Bool
    public var logLevel: LogLevel
    public var databasePath: String?

    public init(
        enableHTTPCapture: Bool = true,
        enableSystemLogCapture: Bool = true,
        enableOSLogCapture: Bool = true,
        logLevel: LogLevel = .debug,
        databasePath: String? = nil
    ) {
        self.enableHTTPCapture = enableHTTPCapture
        self.enableSystemLogCapture = enableSystemLogCapture
        self.enableOSLogCapture = enableOSLogCapture
        self.logLevel = logLevel
        self.databasePath = databasePath
    }
}
