import Foundation
import CoreData

/// Programmatic CoreData model and container setup.
public enum CoreDataStack: Sendable {

    /// Cached model instance — CoreData requires a single shared model
    /// to avoid entity description conflicts across containers.
    nonisolated(unsafe) private static let _sharedModel: NSManagedObjectModel = _buildModel()

    /// Returns the shared managed object model.
    public static func createModel() -> NSManagedObjectModel {
        _sharedModel
    }

    /// Build the managed object model programmatically.
    private static func _buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // MARK: - CDSession Entity

        let sessionEntity = NSEntityDescription()
        sessionEntity.name = "CDSession"
        sessionEntity.managedObjectClassName = "CDSession"

        let sessionID = NSAttributeDescription()
        sessionID.name = "id"
        sessionID.attributeType = .UUIDAttributeType

        let appName = NSAttributeDescription()
        appName.name = "appName"
        appName.attributeType = .stringAttributeType

        let appVersion = NSAttributeDescription()
        appVersion.name = "appVersion"
        appVersion.attributeType = .stringAttributeType
        appVersion.isOptional = true

        let bundleID = NSAttributeDescription()
        bundleID.name = "bundleID"
        bundleID.attributeType = .stringAttributeType
        bundleID.isOptional = true

        let osName = NSAttributeDescription()
        osName.name = "osName"
        osName.attributeType = .stringAttributeType

        let osVersion = NSAttributeDescription()
        osVersion.name = "osVersion"
        osVersion.attributeType = .stringAttributeType

        let deviceModel = NSAttributeDescription()
        deviceModel.name = "deviceModel"
        deviceModel.attributeType = .stringAttributeType

        let startedAt = NSAttributeDescription()
        startedAt.name = "startedAt"
        startedAt.attributeType = .dateAttributeType

        let endedAt = NSAttributeDescription()
        endedAt.name = "endedAt"
        endedAt.attributeType = .dateAttributeType
        endedAt.isOptional = true

        let isCrashed = NSAttributeDescription()
        isCrashed.name = "isCrashed"
        isCrashed.attributeType = .booleanAttributeType
        isCrashed.defaultValue = false

        // MARK: - CDLogEntry Entity

        let logEntryEntity = NSEntityDescription()
        logEntryEntity.name = "CDLogEntry"
        logEntryEntity.managedObjectClassName = "CDLogEntry"

        let logSequenceID = NSAttributeDescription()
        logSequenceID.name = "sequenceID"
        logSequenceID.attributeType = .integer64AttributeType

        let logTimestamp = NSAttributeDescription()
        logTimestamp.name = "timestamp"
        logTimestamp.attributeType = .dateAttributeType

        let logCategory = NSAttributeDescription()
        logCategory.name = "category"
        logCategory.attributeType = .stringAttributeType

        let logLevel = NSAttributeDescription()
        logLevel.name = "level"
        logLevel.attributeType = .stringAttributeType

        let logMessage = NSAttributeDescription()
        logMessage.name = "message"
        logMessage.attributeType = .stringAttributeType

        let logMetadata = NSAttributeDescription()
        logMetadata.name = "metadata"
        logMetadata.attributeType = .stringAttributeType
        logMetadata.isOptional = true

        let logSourceFile = NSAttributeDescription()
        logSourceFile.name = "sourceFile"
        logSourceFile.attributeType = .stringAttributeType
        logSourceFile.isOptional = true

        let logSourceLine = NSAttributeDescription()
        logSourceLine.name = "sourceLine"
        logSourceLine.attributeType = .integer32AttributeType
        logSourceLine.isOptional = true

        // MARK: - CDHTTPEntry Entity

        let httpEntryEntity = NSEntityDescription()
        httpEntryEntity.name = "CDHTTPEntry"
        httpEntryEntity.managedObjectClassName = "CDHTTPEntry"

        let httpMethod = NSAttributeDescription()
        httpMethod.name = "method"
        httpMethod.attributeType = .stringAttributeType

        let httpURL = NSAttributeDescription()
        httpURL.name = "url"
        httpURL.attributeType = .stringAttributeType

        let httpRequestHeaders = NSAttributeDescription()
        httpRequestHeaders.name = "requestHeaders"
        httpRequestHeaders.attributeType = .stringAttributeType
        httpRequestHeaders.isOptional = true

        let httpRequestBody = NSAttributeDescription()
        httpRequestBody.name = "requestBody"
        httpRequestBody.attributeType = .stringAttributeType
        httpRequestBody.isOptional = true

        let httpStatusCode = NSAttributeDescription()
        httpStatusCode.name = "statusCode"
        httpStatusCode.attributeType = .integer32AttributeType
        httpStatusCode.isOptional = true

        let httpResponseHeaders = NSAttributeDescription()
        httpResponseHeaders.name = "responseHeaders"
        httpResponseHeaders.attributeType = .stringAttributeType
        httpResponseHeaders.isOptional = true

        let httpResponseBody = NSAttributeDescription()
        httpResponseBody.name = "responseBody"
        httpResponseBody.attributeType = .stringAttributeType
        httpResponseBody.isOptional = true

        let httpDurationMs = NSAttributeDescription()
        httpDurationMs.name = "durationMs"
        httpDurationMs.attributeType = .doubleAttributeType
        httpDurationMs.isOptional = true

        // MARK: - Relationships

        // Session → LogEntries (one-to-many, cascade delete)
        let sessionToLogEntries = NSRelationshipDescription()
        sessionToLogEntries.name = "logEntries"
        sessionToLogEntries.destinationEntity = logEntryEntity
        sessionToLogEntries.deleteRule = .cascadeDeleteRule
        sessionToLogEntries.isOptional = true
        sessionToLogEntries.maxCount = 0 // to-many

        let logEntryToSession = NSRelationshipDescription()
        logEntryToSession.name = "session"
        logEntryToSession.destinationEntity = sessionEntity
        logEntryToSession.deleteRule = .nullifyDeleteRule
        logEntryToSession.maxCount = 1

        sessionToLogEntries.inverseRelationship = logEntryToSession
        logEntryToSession.inverseRelationship = sessionToLogEntries

        // LogEntry → HTTPEntry (one-to-one, cascade delete)
        let logEntryToHTTP = NSRelationshipDescription()
        logEntryToHTTP.name = "httpEntry"
        logEntryToHTTP.destinationEntity = httpEntryEntity
        logEntryToHTTP.deleteRule = .cascadeDeleteRule
        logEntryToHTTP.isOptional = true
        logEntryToHTTP.maxCount = 1

        let httpToLogEntry = NSRelationshipDescription()
        httpToLogEntry.name = "logEntry"
        httpToLogEntry.destinationEntity = logEntryEntity
        httpToLogEntry.deleteRule = .nullifyDeleteRule
        httpToLogEntry.maxCount = 1

        logEntryToHTTP.inverseRelationship = httpToLogEntry
        httpToLogEntry.inverseRelationship = logEntryToHTTP

        // MARK: - Assign properties to entities

        sessionEntity.properties = [
            sessionID, appName, appVersion, bundleID, osName, osVersion,
            deviceModel, startedAt, endedAt, isCrashed, sessionToLogEntries,
        ]

        logEntryEntity.properties = [
            logSequenceID, logTimestamp, logCategory, logLevel, logMessage,
            logMetadata, logSourceFile, logSourceLine, logEntryToSession, logEntryToHTTP,
        ]

        httpEntryEntity.properties = [
            httpMethod, httpURL, httpRequestHeaders, httpRequestBody,
            httpStatusCode, httpResponseHeaders, httpResponseBody,
            httpDurationMs, httpToLogEntry,
        ]

        model.entities = [sessionEntity, logEntryEntity, httpEntryEntity]
        return model
    }

    /// Create a persistent container with the programmatic model.
    public static func createContainer(name: String = "AgentLogs", at storeURL: URL? = nil) -> NSPersistentContainer {
        let model = createModel()
        let container = NSPersistentContainer(name: name, managedObjectModel: model)

        if let storeURL {
            let description = NSPersistentStoreDescription(url: storeURL)
            container.persistentStoreDescriptions = [description]
        }

        return container
    }

    /// Create a temporary container for testing.
    /// Uses a unique file-based store to avoid CoreData cross-store conflicts.
    public static func createInMemoryContainer() -> NSPersistentContainer {
        let model = createModel()
        let container = NSPersistentContainer(name: "AgentLogs", managedObjectModel: model)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLogs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("test.sqlite")

        let description = NSPersistentStoreDescription(url: storeURL)
        container.persistentStoreDescriptions = [description]

        return container
    }
}
