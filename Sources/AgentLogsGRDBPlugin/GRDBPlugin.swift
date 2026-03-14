import Foundation
import GRDB
import AgentLogsSDK
import AgentLogsCore

/// Logs SQL operations from any GRDB database using trace() API.
///
/// Because GRDB's `trace()` must be configured on the `Database` object
/// (via `Configuration.prepareDatabase`), the plugin provides a static
/// helper to create a GRDB `Configuration` with tracing enabled.
///
/// Usage:
/// ```swift
/// let plugin = GRDBPlugin()
///
/// var dbConfig = Configuration()
/// plugin.installTrace(in: &dbConfig)
/// let database = try DatabaseQueue(path: path, configuration: dbConfig)
///
/// AgentLogs.start(config: .init(
///     collectors: Configuration.defaultCollectors() + [plugin]
/// ))
/// ```
public final class GRDBPlugin: @unchecked Sendable, LogCollector {
    public let category = LogCategory.sqlite

    private var context: CollectorContext?
    private let lock = NSLock()

    public init() {}

    /// Install trace handler into a GRDB Configuration.
    /// Call this before creating the DatabaseQueue/DatabasePool.
    public func installTrace(in config: inout GRDB.Configuration) {
        config.prepareDatabase { [weak self] db in
            db.trace(options: .profile) { event in
                self?.handle(event: event)
            }
        }
    }

    public func start(context: CollectorContext) async {
        setContext(context)
    }

    public func stop() async {
        setContext(nil)
    }

    private func setContext(_ ctx: CollectorContext?) {
        lock.lock()
        self.context = ctx
        lock.unlock()
    }

    private func handle(event: Database.TraceEvent) {
        lock.lock()
        guard let context else { lock.unlock(); return }
        lock.unlock()

        let (message, level) = describe(event)
        let entry = PendingLogEntry(
            sessionID: context.sessionID,
            timestamp: Date(),
            category: .sqlite,
            level: level,
            message: message
        )
        Task {
            await context.sink.append(entry)
        }
    }

    private func describe(_ event: Database.TraceEvent) -> (String, LogLevel) {
        switch event {
        case .profile(let statement, let duration):
            let ms = duration * 1000
            let level: LogLevel = ms > 100 ? .warning : .debug
            return (String(format: "%.1fms %@", ms, statement.sql), level)
        default:
            return ("\(event)", .debug)
        }
    }
}
