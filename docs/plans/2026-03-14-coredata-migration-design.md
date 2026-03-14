# CoreData Migration Design

## Summary

Replace GRDB with CoreData as the internal storage layer in AgentLogsCore and AgentLogsSDK. Keep GRDBPlugin as a separate optional target with its own GRDB dependency.

## Decisions

| Decision | Choice |
|----------|--------|
| Model layer | Two-layer: CoreData NSManagedObjects internal, public struct API unchanged |
| Schema definition | Programmatic (NSManagedObjectModel in code), no .xcdatamodeld |
| CLI storage access | CoreData (same programmatic schema from AgentLogsCore) |
| LogBuffer approach | NSManagedObjectContext with privateQueueConcurrencyType, relationships instead of FK |
| GRDBPlugin | Stays as separate optional target with own GRDB dependency |

## 1. Two-layer models

Internal CoreData entities (`CDSession`, `CDLogEntry`, `CDHTTPEntry`) as NSManagedObject subclasses. Public API continues to return existing structs (`Session`, `LogEntry`, `HTTPEntry`). SDK converts between the two layers.

- Structs remain Sendable, Codable, and are the public contract
- CoreData is an implementation detail hidden inside Core/SDK
- Mapping code lives in extensions on the CD* classes

## 2. Programmatic CoreData schema

`NSManagedObjectModel` built in code (no .xcdatamodeld files). Three entities mirror current tables:

- `CDSession`: id (UUID), appName, appVersion, bundleID, osName, osVersion, deviceModel, startedAt, endedAt, isCrashed
- `CDLogEntry`: timestamp, category, level, message, metadata, sourceFile, sourceLine. Relationship → CDSession (many-to-one). Relationship → CDHTTPEntry (one-to-one, optional).
- `CDHTTPEntry`: method, url, requestHeaders, requestBody, statusCode, responseHeaders, responseBody, durationMs. Relationship → CDLogEntry (one-to-one, inverse).

Cascade delete rules: Session → LogEntry → HTTPEntry.

## 3. LogBuffer with CoreData

```swift
actor LogBuffer: LogSink {
    private let context: NSManagedObjectContext  // privateQueueConcurrencyType

    func performFlush() {
        context.performAndWait {
            for entry in buffer {
                let cdEntry = CDLogEntry(context: context)
                // map fields...
                if let http = entry.httpEntry {
                    let cdHTTP = CDHTTPEntry(context: context)
                    cdHTTP.logEntry = cdEntry  // relationship
                }
            }
            try? context.save()
        }
    }
}
```

Batching (50 entries / 500ms) and actor isolation unchanged.

## 4. CLI reads via CoreData

CLI opens the same .sqlite file using NSPersistentContainer with the same programmatic schema from AgentLogsCore. CLI is macOS-only, CoreData is available.

## 5. Package structure

```
AgentLogsCore          — structs, programmatic CoreData schema, queries
                         dependencies: none (Foundation + CoreData)

AgentLogsSDK           — SDK, collectors, LogBuffer, BonjourServer
                         dependencies: AgentLogsCore, swift-nio

AgentLogsGRDBPlugin    — optional GRDB trace plugin
                         dependencies: AgentLogsSDK, GRDB

AgentLogsCLI           — CLI tool
                         dependencies: AgentLogsCore, swift-argument-parser
```

GRDB removed from Core and SDK. Stays only as GRDBPlugin's own dependency.
Platforms remain iOS 15+ / macOS 12+.
