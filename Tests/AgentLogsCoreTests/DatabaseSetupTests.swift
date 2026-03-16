import Testing
@testable import AgentLogsCore

@Suite("SQLiteStore Setup")
struct SQLiteStoreSetupTests {

    @Test("In-memory store opens successfully")
    func inMemoryStoreOpens() throws {
        let store = try SQLiteStore()
        // Should be able to query without error
        let sessions = try store.fetchSessions()
        #expect(sessions.isEmpty)
    }

    @Test("Store can insert and fetch a session")
    func basicSessionCRUD() throws {
        let store = try SQLiteStore()
        let session = Session(
            appName: "Test",
            osName: "macOS",
            osVersion: "15.0",
            deviceModel: "Mac"
        )
        try store.insertSession(session)

        let sessions = try store.fetchSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].appName == "Test")
    }

    @Test("Creating store twice does not error")
    func storeIdempotent() throws {
        _ = try SQLiteStore()
        _ = try SQLiteStore()
        #expect(Bool(true))
    }
}
