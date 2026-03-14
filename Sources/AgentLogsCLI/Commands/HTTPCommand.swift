import ArgumentParser
import Foundation
import AgentLogsCore

struct HTTP: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "http",
        abstract: "Show full HTTP request/response details for a log entry."
    )

    @OptionGroup var db: DatabaseOptions
    @OptionGroup var output: OutputOptions

    @Argument(help: "The log entry ID to show HTTP details for.")
    var logEntryID: Int

    func run() throws {
        let dataSource = try db.resolveDataSource()

        guard let httpEntry = try dataSource.fetchHTTPEntry(logEntryID: logEntryID) else {
            throw ValidationError("No HTTP entry found for log entry ID \(logEntryID).")
        }

        output.format.printHTTPEntry(httpEntry, logEntry: nil)
    }
}
