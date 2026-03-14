import Testing
import GRDB
@testable import AgentLogsCore

@Suite("DatabaseSetup")
struct DatabaseSetupTests {

    @Test("In-memory database opens successfully")
    func inMemoryDatabaseOpens() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        // Verify the database is usable by performing a simple read
        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master WHERE type='table'")
        }
        #expect(count != nil)
        #expect(count! > 0)
    }

    @Test("Session table is created")
    func sessionTableExists() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        let exists = try db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT count(*) > 0 FROM sqlite_master WHERE type='table' AND name='session'"
            )
        }
        #expect(exists == true)
    }

    @Test("LogEntry table is created")
    func logEntryTableExists() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        let exists = try db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT count(*) > 0 FROM sqlite_master WHERE type='table' AND name='logEntry'"
            )
        }
        #expect(exists == true)
    }

    @Test("HTTPEntry table is created")
    func httpEntryTableExists() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        let exists = try db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT count(*) > 0 FROM sqlite_master WHERE type='table' AND name='httpEntry'"
            )
        }
        #expect(exists == true)
    }

    @Test("All three tables are created")
    func allTablesCreated() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        let tableNames = try db.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('session', 'logEntry', 'httpEntry') ORDER BY name"
            )
        }
        #expect(tableNames == ["httpEntry", "logEntry", "session"])
    }

    @Test("Indices exist on logEntry table")
    func indicesExist() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        let indexNames = try db.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_logEntry_%' ORDER BY name"
            )
        }
        #expect(indexNames.contains("idx_logEntry_sessionID"))
        #expect(indexNames.contains("idx_logEntry_timestamp"))
        #expect(indexNames.contains("idx_logEntry_category"))
        #expect(indexNames.contains("idx_logEntry_level"))
        #expect(indexNames.count == 4)
    }

    @Test("Migrator is idempotent — running twice does not error")
    func migratorIdempotent() throws {
        let db = try DatabaseSetup.openInMemoryDatabase()
        // Run migrator again on the same database
        let migrator = DatabaseSetup.createMigrator()
        try migrator.migrate(db)
        // Should still have exactly 3 tables
        let tableCount = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('session', 'logEntry', 'httpEntry')"
            )
        }
        #expect(tableCount == 3)
    }
}
