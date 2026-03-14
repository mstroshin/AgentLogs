import ArgumentParser
import Foundation
import AgentLogsCore

struct Sessions: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List recorded sessions."
    )

    @OptionGroup var db: DatabaseOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Show only crashed sessions.")
    var crashed: Bool = false

    @Option(name: .long, help: "Maximum number of sessions to return.")
    var limit: Int = 50

    func run() throws {
        let dataSource = try db.resolveDataSource()
        let sessions = try dataSource.fetchSessions(crashedOnly: crashed, limit: limit)

        output.format.printSessions(sessions)
    }
}
