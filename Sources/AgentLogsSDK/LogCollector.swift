import Foundation
import AgentLogsCore

/// Public interface for writing log entries. Plugins use this to append logs.
public protocol LogSink: Sendable {
    func append(_ entry: PendingLogEntry) async
}

/// Context provided by the SDK to each collector when it starts.
public struct CollectorContext: Sendable {
    public let sink: any LogSink
    public let sessionID: UUID

    public init(sink: any LogSink, sessionID: UUID) {
        self.sink = sink
        self.sessionID = sessionID
    }
}

/// Protocol for all log collectors — built-in and external plugins.
public protocol LogCollector: Sendable {
    /// The category under which this collector's entries are recorded.
    var category: LogCategory { get }

    /// Start collecting logs. Called by the SDK after session and buffer are ready.
    func start(context: CollectorContext) async

    /// Stop collecting logs. Called by the SDK during shutdown.
    func stop() async
}
