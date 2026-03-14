import Testing
import Foundation
@testable import AgentLogsSDK
import AgentLogsCore

@Suite("Configuration")
struct ConfigurationTests {

    @Test("Default configuration has expected values")
    func defaultConfiguration() {
        let config = Configuration()
        #expect(config.collectors.count >= 2) // HTTP + OSLog at minimum; +System on Darwin
        #expect(config.logLevel == .debug)
        #expect(config.databasePath == nil)
    }

    @Test("Custom configuration with explicit collectors")
    func customCollectors() {
        let config = Configuration(
            collectors: [HTTPCollector()],
            logLevel: .error,
            databasePath: "/tmp/test.sqlite"
        )
        #expect(config.collectors.count == 1)
        #expect(config.logLevel == .error)
        #expect(config.databasePath == "/tmp/test.sqlite")
    }

    @Test("Nil collectors uses default set")
    func nilCollectorsUsesDefaults() {
        let config = Configuration(collectors: nil)
        #expect(config.collectors.count == Configuration.defaultCollectors().count)
    }

    @Test("Empty collectors array is valid")
    func emptyCollectors() {
        let config = Configuration(collectors: [])
        #expect(config.collectors.isEmpty)
    }

    @Test("defaultCollectors includes HTTPCollector")
    func defaultCollectorsIncludesHTTP() {
        let collectors = Configuration.defaultCollectors()
        let hasHTTP = collectors.contains { $0 is HTTPCollector }
        #expect(hasHTTP)
    }

    @Test("defaultCollectors includes OSLogCollector")
    func defaultCollectorsIncludesOSLog() {
        let collectors = Configuration.defaultCollectors()
        let hasOSLog = collectors.contains { $0 is OSLogCollector }
        #expect(hasOSLog)
    }

    @Test("Configuration is Sendable")
    func sendable() {
        let config = Configuration()
        let _: any Sendable = config
        #expect(Bool(true))
    }
}
