import ArgumentParser
import Foundation
import AgentLogsCore

struct DatabaseOptions: ParsableArguments, Sendable {
    @Option(name: .long, help: "Path to the SQLite database file. Defaults to auto-discovery of simulator databases.")
    var dbPath: String?

    @Option(name: .long, help: "Connect to a remote device at host:port instead of reading local SQLite.")
    var remote: String?

    func resolveDataSource() throws -> LogDataSource {
        if let remote {
            let parts = remote.split(separator: ":")
            guard parts.count == 2, let port = Int(parts[1]) else {
                throw ValidationError("--remote must be in the format host:port")
            }
            return try NetworkDataSource(host: String(parts[0]), port: port)
        }

        let path: String
        if let dbPath {
            path = dbPath
        } else if let db = SimulatorDiscovery.mostRecentDatabase() {
            path = db.path
        } else {
            throw ValidationError(
                "No database found. Specify --db-path or ensure a simulator has an AgentLogs database."
            )
        }
        return try CoreDataDataSource(path: path)
    }
}

enum OutputFormat: String, Sendable {
    case human
    case json
    case toon

    func printLogs(_ entries: [LogEntry]) {
        switch self {
        case .human:
            print(HumanFormatter.formatLogs(entries))
        case .json:
            print(JSONFormatter.formatLogs(entries))
        case .toon:
            print(ToonFormatter.formatLogs(entries))
        }
    }

    func printSessions(_ sessions: [Session]) {
        switch self {
        case .human:
            print(HumanFormatter.formatSessions(sessions))
        case .json:
            print(JSONFormatter.formatSessions(sessions))
        case .toon:
            print(ToonFormatter.formatSessions(sessions))
        }
    }

    func printHTTPEntry(_ entry: HTTPEntry, logEntry: LogEntry?) {
        switch self {
        case .human:
            print(HumanFormatter.formatHTTPEntry(entry, logEntry: logEntry))
        case .json:
            print(JSONFormatter.formatHTTPEntry(entry))
        case .toon:
            print(ToonFormatter.formatHTTPEntry(entry))
        }
    }
}

// MARK: - Shared Helpers

func resolveSessionID(_ raw: String, from dataSource: LogDataSource) throws -> UUID {
    if raw.lowercased() == "latest" {
        guard let id = try dataSource.latestSessionID() else {
            throw ValidationError("No sessions found in the database.")
        }
        return id
    }
    guard let id = UUID(uuidString: raw) else {
        throw ValidationError("Invalid session ID '\(raw)'. Provide a valid UUID or 'latest'.")
    }
    return id
}

// MARK: - ExpressibleByArgument Conformances

extension LogLevel: ExpressibleByArgument {}
extension LogCategory: ExpressibleByArgument {}

struct OutputOptions: ParsableArguments, Sendable {
    @Flag(name: .long, help: "Output as JSON.")
    var json: Bool = false

    @Flag(name: .long, help: "Output in token-optimized format.")
    var toon: Bool = false

    var format: OutputFormat {
        if json { return .json }
        if toon { return .toon }
        return .human
    }
}
