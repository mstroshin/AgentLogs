# Plugin System Design

## Summary

Formalize the collector pattern into a `LogCollector` protocol, refactor all existing collectors to conform, make `LogCategory` extensible, and add a `GRDBPlugin` for SQL query logging.

## Decisions

| Decision | Choice |
|----------|--------|
| LogCategory | struct with RawRepresentable (not enum) |
| Collector init pattern | `start(context:)` — SDK injects buffer/sessionID |
| GRDBPlugin location | Separate target `AgentLogsGRDBPlugin` |
| Existing collectors | Refactor to conform to `LogCollector` |
| `custom` category | Renamed to `manualLogs` |

## 1. LogCategory — enum to struct

```swift
public struct LogCategory: RawRepresentable, Hashable, Sendable, Codable,
                           DatabaseValueConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let http       = LogCategory(rawValue: "http")
    public static let system     = LogCategory(rawValue: "system")
    public static let oslog      = LogCategory(rawValue: "oslog")
    public static let manualLogs = LogCategory(rawValue: "manualLogs")
}
```

Database stores raw strings — fully backward compatible. Old `"custom"` entries remain readable.

## 2. LogCollector protocol

```swift
public protocol LogSink: Sendable {
    func append(_ entry: PendingLogEntry) async
}

public struct CollectorContext: Sendable {
    public let sink: any LogSink
    public let sessionID: UUID
}

public protocol LogCollector: Sendable {
    var category: LogCategory { get }
    func start(context: CollectorContext) async
    func stop() async
}
```

- `LogBuffer` conforms to `LogSink`, exposing only `append()`
- `PendingLogEntry` becomes public
- `PendingHTTPEntry` stays internal

## 3. Configuration refactor

```swift
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
        [HTTPCollector(), SystemLogCollector(), OSLogCollector()]
    }
}
```

## 4. State actor refactor

Replace individual collector properties with `collectors: [any LogCollector]`.

Start:
```swift
for collector in config.collectors {
    await collector.start(context: CollectorContext(sink: logBuffer, sessionID: sessionID))
}
```

Stop:
```swift
for collector in components.collectors {
    await collector.stop()
}
```

## 5. Existing collectors refactor

All three (HTTPCollector, SystemLogCollector, OSLogCollector) conform to `LogCollector`:
- Remove `buffer` and `sessionID` from init
- Receive them via `start(context:)`
- Store context internally (lock-protected for `@unchecked Sendable` types)

## 6. GRDBPlugin (AgentLogsGRDBPlugin target)

GRDB's `trace()` is defined on `Database`, not `DatabaseQueue`/`DatabasePool`.
The plugin uses `Configuration.prepareDatabase` to install the trace handler.

```swift
public final class GRDBPlugin: LogCollector, @unchecked Sendable {
    public let category = LogCategory.sqlite

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

    public func start(context: CollectorContext) async { ... }
    public func stop() async { ... }
}
```

- Slow queries (>100ms) logged as `.warning`
- Category: `.sqlite` (defined in `LogCategory` extension in plugin target)

## 7. Package structure

```
AgentLogsCore          — models, DB schema, queries
AgentLogsSDK           — SDK, built-in collectors, LogCollector protocol
AgentLogsGRDBPlugin    — GRDBPlugin (trace-based SQL logging)
AgentLogsCLI           — CLI tool
```

Package.swift addition:
```swift
.library(name: "AgentLogsGRDBPlugin", targets: ["AgentLogsGRDBPlugin"]),

.target(
    name: "AgentLogsGRDBPlugin",
    dependencies: [
        "AgentLogsSDK",
        .product(name: "GRDB", package: "GRDB.swift"),
    ]
)
```

## Usage

```swift
import AgentLogsSDK
import AgentLogsGRDBPlugin

let plugin = GRDBPlugin()

var dbConfig = GRDB.Configuration()
plugin.installTrace(in: &dbConfig)
let database = try DatabaseQueue(path: path, configuration: dbConfig)

AgentLogs.start(config: .init(
    collectors: Configuration.defaultCollectors() + [plugin]
))
```
