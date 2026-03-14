import ArgumentParser
import Foundation
import AgentLogsCore

struct Search: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search log entries by message content."
    )

    @OptionGroup var db: DatabaseOptions
    @OptionGroup var output: OutputOptions

    @Argument(help: "The search query string.")
    var query: String

    @Option(name: .long, help: "Restrict search to a specific session ID.")
    var session: String?

    @Option(name: .long, help: "Filter by log level (debug, info, warning, error, critical).")
    var level: LogLevel?

    @Option(name: .long, help: "Filter by category (http, system, oslog, custom).")
    var category: LogCategory?

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int = 100

    func run() throws {
        let dataSource = try db.resolveDataSource()

        let sessionUUID: UUID? = try session.map { raw in
            guard let id = UUID(uuidString: raw) else {
                throw ValidationError("Invalid session ID '\(raw)'.")
            }
            return id
        }

        let entries = try dataSource.searchLogs(
            query: query,
            sessionID: sessionUUID,
            category: category,
            level: level,
            limit: limit
        )

        output.format.printLogs(entries)
    }
}
