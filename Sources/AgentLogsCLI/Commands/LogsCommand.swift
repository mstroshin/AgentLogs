import ArgumentParser
import Foundation
import AgentLogsCore

struct Logs: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Fetch log entries for a session."
    )

    @OptionGroup var db: DatabaseOptions
    @OptionGroup var output: OutputOptions

    @Argument(help: "Session ID (UUID) or \"latest\" to use the most recent session.")
    var sessionID: String

    @Option(name: .long, help: "Filter by log level (debug, info, warning, error, critical).")
    var level: LogLevel?

    @Option(name: .long, help: "Filter by category (http, system, oslog, manualLogs, or any plugin category).")
    var category: LogCategory?

    @Option(name: .long, help: "Maximum number of log entries to return.")
    var limit: Int = 500

    func run() throws {
        let dataSource = try db.resolveDataSource()
        let resolvedID = try resolveSessionID(sessionID, from: dataSource)

        let entries = try dataSource.fetchLogs(
            sessionID: resolvedID,
            category: category,
            level: level,
            limit: limit
        )

        output.format.printLogs(entries)
    }
}
