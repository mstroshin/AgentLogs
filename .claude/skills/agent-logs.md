---
name: agent-logs
description: Debug iOS/macOS applications using the agent-logs CLI tool to inspect app sessions, logs, and HTTP traffic.
---

# agent-logs CLI

A CLI tool for debugging iOS/macOS applications by inspecting logs from simulator databases and physical devices.

## Commands

| Command | Purpose |
|---|---|
| `agent-logs sessions` | List app sessions. Flags: `--crashed`, `--limit N`, `--json`, `--toon` |
| `agent-logs logs <session-id\|latest>` | View logs for a session. Flags: `--level`, `--category`, `--limit N`, `--json`, `--toon` |
| `agent-logs tail [session-id]` | Real-time log tailing. Flags: `--after`, `--toon` |
| `agent-logs http <log-entry-id>` | Show HTTP request/response details. Flags: `--json`, `--toon` |
| `agent-logs search <query>` | Search across logs. Flags: `--session`, `--category`, `--level`, `--limit N`, `--json`, `--toon` |
| `agent-logs devices` | List available simulators and physical devices. |

## Token-saving rules

- ALWAYS pass `--toon` to get compact output. This is critical for keeping context usage low.
- Only use `--json` or omit `--toon` when you need full details of a specific entry (e.g., inspecting one HTTP response body).

## Log levels

`debug`, `info`, `warning`, `error`, `critical`

## Log categories

`http`, `system`, `oslog`, `custom`

## Debugging workflow

1. **Start with sessions** to understand what ran recently:
   ```
   agent-logs sessions --toon
   ```
2. **Check errors** in the latest session:
   ```
   agent-logs logs latest --level error --toon
   ```
3. **Narrow by category** if needed:
   ```
   agent-logs logs latest --level error --category http --toon
   ```
4. **Inspect a specific HTTP call** when you find a suspicious log entry:
   ```
   agent-logs http <log-entry-id> --json
   ```
5. **Search across sessions** for a known error string:
   ```
   agent-logs search "timeout" --level error --toon
   ```
6. **Monitor in real time** while reproducing a bug:
   ```
   agent-logs tail --toon
   ```

## Device discovery

The tool auto-discovers simulator databases. For physical devices, run `agent-logs devices` first to find the device identifier, then pass it where needed.

## Crash investigation

Use `agent-logs sessions --crashed --toon` to list only sessions that ended in a crash, then inspect their logs.
