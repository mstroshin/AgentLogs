import Foundation
import GRDB

public enum DatabaseSetup: Sendable {
    public static func createMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-create-tables") { db in
            try db.create(table: "session") { t in
                t.column("id", .text).primaryKey()
                t.column("appName", .text).notNull()
                t.column("appVersion", .text)
                t.column("bundleID", .text)
                t.column("osName", .text).notNull()
                t.column("osVersion", .text).notNull()
                t.column("deviceModel", .text).notNull()
                t.column("startedAt", .double).notNull()
                t.column("endedAt", .double)
                t.column("isCrashed", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "logEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionID", .text).notNull()
                    .references("session", onDelete: .cascade)
                t.column("timestamp", .double).notNull()
                t.column("category", .text).notNull()
                t.column("level", .text).notNull()
                t.column("message", .text).notNull()
                t.column("metadata", .text)
                t.column("sourceFile", .text)
                t.column("sourceLine", .integer)
            }

            try db.create(table: "httpEntry") { t in
                t.column("logEntryID", .integer).primaryKey()
                    .references("logEntry", onDelete: .cascade)
                t.column("method", .text).notNull()
                t.column("url", .text).notNull()
                t.column("requestHeaders", .text)
                t.column("requestBody", .text)
                t.column("statusCode", .integer)
                t.column("responseHeaders", .text)
                t.column("responseBody", .text)
                t.column("durationMs", .double)
            }

            // Composite indices: leftmost prefix covers single-column queries on sessionID
            try db.create(index: "idx_logEntry_sessionID", on: "logEntry", columns: ["sessionID", "id"])
            try db.create(index: "idx_logEntry_timestamp", on: "logEntry", columns: ["sessionID", "timestamp"])
            try db.create(index: "idx_logEntry_category", on: "logEntry", columns: ["category"])
            try db.create(index: "idx_logEntry_level", on: "logEntry", columns: ["level"])
        }

        return migrator
    }

    public static func openDatabase(at path: String) throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(path: path)
        try createMigrator().migrate(dbQueue)
        return dbQueue
    }

    public static func openInMemoryDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try createMigrator().migrate(dbQueue)
        return dbQueue
    }
}
