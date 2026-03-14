import ArgumentParser
import AgentLogsCore

struct AgentLogsCLITool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-logs",
        abstract: "CLI tool for inspecting AgentLogs databases.",
        subcommands: [Sessions.self, Logs.self, Tail.self, HTTP.self, Search.self, Devices.self]
    )
}

AgentLogsCLITool.main()
