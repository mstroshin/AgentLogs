# AgentLogs

A Swift library that collects iOS/macOS app logs and exposes them via a built-in UI viewer and CLI for debugging.

## What is it

AgentLogs automatically captures HTTP traffic, system logs (`print`, `os_log`), and custom messages into a CoreData store. View logs on-device with `AgentLogs.showUI()`, or use the `agent-logs` CLI for Claude Code debugging.

## Requirements

- iOS 15+ / macOS 12+
- Swift 6.1+
- Xcode 16+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mstroshin/AgentLogs", from: "2.0.0"),
]
```

Add the products you need:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AgentLogsSDK", package: "AgentLogs"),
        .product(name: "AgentLogsUI", package: "AgentLogs"),  // optional, iOS only
    ]
)
```

## Quick Start

### 1. Integrate the SDK

```swift
import AgentLogsSDK

// On app launch
AgentLogs.start()

// Log messages
AgentLogs.log("User tapped login button")
AgentLogs.log("Failed to load profile", type: .error)

// On termination (optional — SDK handles shutdown automatically)
AgentLogs.stop()
```

### 2. View Logs On-Device (iOS)

```swift
import AgentLogsUI

// Show the log viewer from anywhere — button, shake handler, debug menu
AgentLogs.showUI()
```

Or present as a SwiftUI sheet:

```swift
.sheet(isPresented: $showLogs) {
    AgentLogsView()
}
```

The built-in viewer provides:
- Live-updating log list with color-coded severity levels
- Category and level filters
- Full-text search
- Log detail view with source location
- HTTP request/response inspector

### 3. Install the CLI

```bash
swift build -c release --product agent-logs
cp .build/release/agent-logs /usr/local/bin/
```

### 4. Set Up the Claude Code Skill

Copy `.claude/skills/agent-logs.md` into your project. Claude Code will automatically use the CLI when debugging.

## SDK

### Configuration

```swift
AgentLogs.start(config: .init(
    collectors: Configuration.defaultCollectors(),  // HTTP + System + OSLog
    logLevel: .debug,
    databasePath: nil  // nil = default path
))
```

Customize collectors:

```swift
AgentLogs.start(config: .init(
    collectors: [HTTPCollector(), OSLogCollector()],  // no stdout capture
    logLevel: .warning
))
```

### Plugin System

The SDK uses a `LogCollector` protocol. Built-in collectors (HTTP, System, OSLog) and external plugins conform to the same interface:

```swift
public protocol LogCollector: Sendable {
    var category: LogCategory { get }
    func start(context: CollectorContext) async
    func stop() async
}
```

**GRDB Plugin** — optional target for monitoring SQL queries in apps using GRDB:

```swift
// Package.swift
.product(name: "AgentLogsGRDBPlugin", package: "AgentLogs"),

// Usage
import AgentLogsGRDBPlugin

let plugin = GRDBPlugin()
plugin.installTrace(in: &dbConfig)

AgentLogs.start(config: .init(
    collectors: Configuration.defaultCollectors() + [plugin]
))
```

### Extensible Categories

`LogCategory` is an open struct — plugins define their own:

```swift
extension LogCategory {
    public static let sqlite = LogCategory(rawValue: "sqlite")
    public static let analytics = LogCategory(rawValue: "analytics")
}
```

### API

```swift
AgentLogs.log(_ message: String, type: LogLevel = .info, file: String = #file, line: Int = #line)
```

Levels: `.debug`, `.info`, `.warning`, `.error`, `.critical`

### Auto-Captured Data

| Category | Source | How it works |
|----------|--------|--------------|
| `http` | URLSession | URLProtocol intercepts all requests |
| `system` | print() | dup2 + Pipe redirects stdout/stderr |
| `oslog` | os_log | Polls OSLogStore every 2 seconds |
| `manualLogs` | AgentLogs.log() | Direct API call |

### Conditional Compilation

The SDK is active only in Debug builds. To enable in Release:

```swift
// Build Settings → Swift Compiler - Custom Flags
-D AGENTLOGS_ENABLED
```

### Physical Devices

On a physical device, the SDK automatically starts an HTTP server and advertises it via Bonjour (`_agentlogs._tcp`). The CLI discovers the device over the local network.

## CLI

### Commands

```bash
# List sessions
agent-logs sessions
agent-logs sessions --crashed

# View session logs
agent-logs logs latest
agent-logs logs <session-id> --level error
agent-logs logs <session-id> --category http

# Real-time monitoring
agent-logs tail
agent-logs tail <session-id>

# HTTP request details
agent-logs http <log-entry-id>

# Search
agent-logs search "timeout"
agent-logs search "500" --category http

# Device discovery
agent-logs devices
```

### Output Formats

**Human-readable** (default):
```
[14:32:01] ERROR [HTTP] POST /api/users -> 500 (234ms)
[14:32:01] ERROR [MANUALLOGS] Failed to parse user response
           at UserService.swift:42
```

**Token-optimized** (`--toon`) — designed for Claude Code:
```
14:32:01|ERR|http|POST /api/users->500 234ms
14:32:01|ERR|man|Parse fail@UserService.swift:42
```

**JSON** (`--json`) — for scripts and integrations.

### Database Connection

```bash
# Auto-discovery (searches simulator databases)
agent-logs sessions

# Explicit path
agent-logs sessions --db-path ~/path/to/agent-logs.sqlite

# Connect to a physical device
agent-logs sessions --remote 192.168.1.42:8080
```

## Architecture

```
┌─────────────────────────────────┐
│         iOS/macOS App           │
│                                 │
│  ┌───────────────────────────┐  │
│  │      AgentLogsSDK         │  │
│  │  ┌─────────────────────┐  │  │
│  │  │   LogCollectors     │  │  │
│  │  │  HTTP · System · OS │  │  │
│  │  │  + custom plugins   │  │  │
│  │  └──────────┬──────────┘  │  │
│  │             │              │  │
│  │       ┌─────▼─────┐       │  │
│  │       │ LogBuffer  │       │  │
│  │       └─────┬─────┘       │  │
│  │             │              │  │
│  │       ┌─────▼─────┐       │  │
│  │       │  CoreData  │       │  │
│  │       └───────────┘       │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │     AgentLogsUI (iOS)     │  │
│  │  AgentLogs.showUI()       │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│       agent-logs CLI            │
│  (reads CoreData / Bonjour)    │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│         Claude Code             │
│       (via Bash + Skill)        │
└─────────────────────────────────┘
```

### Package Structure

```
Sources/
├── AgentLogsCore/       — Models, CoreData schema, queries
├── AgentLogsSDK/        — App SDK (collectors, buffer, Bonjour server)
├── AgentLogsUI/         — SwiftUI log viewer (iOS)
├── AgentLogsGRDBPlugin/ — Optional GRDB trace plugin
└── AgentLogsCLI/        — CLI tool (commands, formatters, data sources)
```

## License

MIT
