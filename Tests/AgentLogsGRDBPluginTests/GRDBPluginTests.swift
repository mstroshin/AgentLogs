import Testing
import Foundation
import GRDB
import AgentLogsCore
@testable import AgentLogsGRDBPlugin
import AgentLogsSDK

/// Mock LogSink that captures appended entries for verification.
actor MockLogSink: LogSink {
    var entries: [PendingLogEntry] = []

    func append(_ entry: PendingLogEntry) {
        entries.append(entry)
    }

    func getEntries() -> [PendingLogEntry] {
        entries
    }
}

@Suite("GRDBPlugin")
struct GRDBPluginTests {

    @Test("Plugin captures SQL trace events")
    func capturesTraceEvents() async throws {
        let plugin = GRDBPlugin()

        var config = GRDB.Configuration()
        plugin.installTrace(in: &config)

        let db = try DatabaseQueue(configuration: config)
        let sink = MockLogSink()

        let context = CollectorContext(sink: sink, sessionID: UUID())
        await plugin.start(context: context)

        // Create a table and insert data to generate SQL events
        try await db.write { database in
            try database.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
            try database.execute(sql: "INSERT INTO test (name) VALUES (?)", arguments: ["hello"])
        }

        // Give trace callbacks time to dispatch
        try await Task.sleep(nanoseconds: 500_000_000)

        let entries = await sink.getEntries()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.category == .sqlite })

        await plugin.stop()
    }

    @Test("Plugin ignores events before start")
    func ignoresBeforeStart() async throws {
        let plugin = GRDBPlugin()

        var config = GRDB.Configuration()
        plugin.installTrace(in: &config)

        let db = try DatabaseQueue(configuration: config)
        let sink = MockLogSink()

        // Execute SQL before start — should not capture
        try await db.write { database in
            try database.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let context = CollectorContext(sink: sink, sessionID: UUID())
        await plugin.start(context: context)

        let entries = await sink.getEntries()
        #expect(entries.isEmpty)

        await plugin.stop()
    }

    @Test("Plugin stops capturing after stop()")
    func stopsCapturing() async throws {
        let plugin = GRDBPlugin()

        var config = GRDB.Configuration()
        plugin.installTrace(in: &config)

        let db = try DatabaseQueue(configuration: config)
        let sink = MockLogSink()

        let context = CollectorContext(sink: sink, sessionID: UUID())
        await plugin.start(context: context)

        try await db.write { database in
            try database.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        await plugin.stop()

        let countAfterStop = await sink.getEntries().count

        // Execute more SQL after stop — should not be captured
        try await db.write { database in
            try database.execute(sql: "INSERT INTO test (id) VALUES (1)")
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        let countLater = await sink.getEntries().count
        #expect(countLater == countAfterStop)
    }

    @Test("Plugin category is sqlite")
    func categoryIsSQLite() {
        let plugin = GRDBPlugin()
        #expect(plugin.category == .sqlite)
    }

    @Test("LogCategory.sqlite has correct rawValue")
    func sqliteCategoryRawValue() {
        #expect(LogCategory.sqlite.rawValue == "sqlite")
    }
}
