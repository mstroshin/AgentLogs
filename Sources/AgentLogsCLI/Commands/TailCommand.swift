import ArgumentParser
import Foundation
import AgentLogsCore

struct Tail: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "tail",
        abstract: "Follow log entries in real-time."
    )

    @OptionGroup var db: DatabaseOptions

    @Argument(help: "Session ID (UUID) or \"latest\". Defaults to latest if omitted.")
    var sessionID: String?

    @Option(name: .long, help: "Only show entries with id greater than this value (for incremental polling).")
    var after: Int = 0

    @Flag(name: .long, help: "Output in token-optimized format.")
    var toon: Bool = false

    func run() throws {
        let dataSource = try db.resolveDataSource()
        let raw = sessionID ?? "latest"
        let resolvedID = try resolveSessionID(raw, from: dataSource)

        var lastID = after

        // Print a header
        if toon {
            print("tail|\(resolvedID.uuidString)")
        } else {
            print("Tailing session \(resolvedID.uuidString) (Ctrl+C to stop)...")
        }

        // Flush stdout so the header appears immediately
        fflush(stdout)

        while true {
            let entries = try dataSource.tailLogs(sessionID: resolvedID, afterID: lastID)
            for entry in entries {
                if toon {
                    print(ToonFormatter.formatLogEntry(entry))
                } else {
                    print(HumanFormatter.formatLogEntry(entry))
                }
                if entry.id > lastID {
                    lastID = entry.id
                }
            }
            if !entries.isEmpty {
                fflush(stdout)
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

}
