# AgentLogs

A Swift library that collects iOS/macOS app logs and exposes them via CLI for Claude Code debugging.

## What is it

AgentLogs automatically captures HTTP traffic, system logs (`print`, `os_log`), and custom messages into a SQLite database. The `agent-logs` CLI lets Claude Code read these logs and assist with debugging.

## Requirements

- iOS 15+ / macOS 12+
- Swift 6.1+
- Xcode 16+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mstroshin/AgentLogs", from: "1.0.0"),
]
```

Add the SDK to your app target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AgentLogsSDK", package: "AgentLogs"),
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
AgentLogs.log("Cache miss", type: .warning, file: #file, line: #line)

// On termination (optional — SDK handles shutdown automatically)
AgentLogs.stop()
```

### 2. Install the CLI

```bash
# From the repository root
swift build -c release --product agent-logs

# Copy to PATH
cp .build/release/agent-logs /usr/local/bin/
```

### 3. Set Up the Claude Code Skill

Copy `.claude/skills/agent-logs.md` into your project. Claude Code will automatically use the CLI when debugging.

## SDK

### Configuration

```swift
AgentLogs.start(config: .init(
    enableHTTPCapture: true,       // Intercept URLSession requests
    enableSystemLogCapture: true,  // Capture stdout/stderr (print)
    enableOSLogCapture: true,      // Read OSLog entries
    logLevel: .debug,              // Minimum log level to record
    databasePath: nil              // nil = default path
))
```

### API

A single method for all logs:

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
| `custom` | AgentLogs.log() | Direct API call |

### Conditional Compilation

The SDK is active only in Debug builds. To enable in Release, add a compiler flag:

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
agent-logs logs latest                       # most recent session
agent-logs logs <session-id> --level error   # errors only
agent-logs logs <session-id> --category http # HTTP only

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
[14:32:01] ERROR [Custom] Failed to parse user response
           at UserService.swift:42
```

**Token-optimized** (`--toon`) — designed for Claude Code:
```
14:32:01|ERR|http|POST /api/users->500 234ms
14:32:01|ERR|cst|Parse fail@UserService.swift:42
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
┌─────────────────────────────┐
│       iOS/macOS App         │
│                             │
│  ┌───────────────────────┐  │
│  │    AgentLogsSDK       │  │
│  │  ┌─────────────────┐  │  │
│  │  │  HTTPCollector   │  │  │
│  │  │  SystemCollector │  │  │
│  │  │  OSLogCollector  │  │  │
│  │  │  Custom logs     │  │  │
│  │  └────────┬────────┘  │  │
│  │           │           │  │
│  │     ┌─────▼─────┐    │  │
│  │     │ LogBuffer  │    │  │
│  │     └─────┬─────┘    │  │
│  │           │           │  │
│  │     ┌─────▼─────┐    │  │
│  │     │  SQLite    │    │  │
│  │     └───────────┘    │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│     agent-logs CLI          │
│  (reads SQLite / Bonjour)   │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│       Claude Code           │
│     (via Bash + Skill)      │
└─────────────────────────────┘
```

### Package Structure

```
Sources/
├── AgentLogsCore/    — Models, database, queries (GRDB)
├── AgentLogsSDK/     — App SDK (collectors, buffer, Bonjour server)
└── AgentLogsCLI/     — CLI tool (commands, formatters, data sources)
```

## License

MIT
