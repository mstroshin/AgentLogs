import Testing
import CoreData
@testable import AgentLogsCore

@Suite("CoreDataStack")
struct CoreDataStackTests {

    private func makeContainer() throws -> NSPersistentContainer {
        let container = CoreDataStack.createInMemoryContainer()
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    @Test("In-memory container opens successfully")
    func inMemoryContainerOpens() throws {
        let container = try makeContainer()
        #expect(container.persistentStoreCoordinator.persistentStores.count > 0)
    }

    @Test("CDSession entity exists")
    func sessionEntityExists() throws {
        let model = CoreDataStack.createModel()
        let entity = model.entitiesByName["CDSession"]
        #expect(entity != nil)
    }

    @Test("CDLogEntry entity exists")
    func logEntryEntityExists() throws {
        let model = CoreDataStack.createModel()
        let entity = model.entitiesByName["CDLogEntry"]
        #expect(entity != nil)
    }

    @Test("CDHTTPEntry entity exists")
    func httpEntryEntityExists() throws {
        let model = CoreDataStack.createModel()
        let entity = model.entitiesByName["CDHTTPEntry"]
        #expect(entity != nil)
    }

    @Test("All three entities are created")
    func allEntitiesCreated() throws {
        let model = CoreDataStack.createModel()
        let names = Set(model.entities.map { $0.name ?? "" })
        #expect(names.contains("CDSession"))
        #expect(names.contains("CDLogEntry"))
        #expect(names.contains("CDHTTPEntry"))
        #expect(model.entities.count == 3)
    }

    @Test("Container can perform basic CRUD")
    func basicCRUD() throws {
        let container = try makeContainer()
        let context = container.viewContext

        let session = CDSession(context: context)
        session.id = UUID()
        session.appName = "Test"
        session.osName = "macOS"
        session.osVersion = "15.0"
        session.deviceModel = "Mac"
        session.startedAt = Date()
        try context.save()

        let request = NSFetchRequest<CDSession>(entityName: "CDSession")
        let count = try context.count(for: request)
        #expect(count == 1)
    }

    @Test("Creating container twice does not error")
    func containerIdempotent() throws {
        _ = try makeContainer()
        _ = try makeContainer()
        #expect(Bool(true))
    }
}
