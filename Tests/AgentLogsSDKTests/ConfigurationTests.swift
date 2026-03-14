import Testing
import Foundation
@testable import AgentLogsSDK
import AgentLogsCore

@Suite("Configuration")
struct ConfigurationTests {

    @Test("Default configuration has expected values")
    func defaultConfiguration() {
        let config = Configuration()
        #expect(config.enableHTTPCapture == true)
        #expect(config.enableSystemLogCapture == true)
        #expect(config.enableOSLogCapture == true)
        #expect(config.logLevel == .debug)
        #expect(config.databasePath == nil)
    }

    @Test("Custom configuration preserves all values")
    func customConfiguration() {
        let config = Configuration(
            enableHTTPCapture: false,
            enableSystemLogCapture: false,
            enableOSLogCapture: false,
            logLevel: .error,
            databasePath: "/tmp/test.sqlite"
        )
        #expect(config.enableHTTPCapture == false)
        #expect(config.enableSystemLogCapture == false)
        #expect(config.enableOSLogCapture == false)
        #expect(config.logLevel == .error)
        #expect(config.databasePath == "/tmp/test.sqlite")
    }

    @Test("Configuration with only some custom values")
    func partialCustomConfiguration() {
        let config = Configuration(
            enableHTTPCapture: false,
            logLevel: .warning
        )
        #expect(config.enableHTTPCapture == false)
        #expect(config.enableSystemLogCapture == true)
        #expect(config.enableOSLogCapture == true)
        #expect(config.logLevel == .warning)
        #expect(config.databasePath == nil)
    }

    @Test("Configuration is Sendable")
    func sendable() {
        let config = Configuration()
        // If this compiles, Configuration is Sendable
        let _: any Sendable = config
        #expect(Bool(true))
    }
}
