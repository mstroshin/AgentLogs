# AgentLogs — Design Document

Библиотека для iOS/macOS, которая собирает логи приложения и предоставляет их Claude Code для помощи в дебаге.

## Общая архитектура

Система состоит из **трёх компонентов**:

### 1. AgentLogsCore (shared)
Общие модели данных и работа с SQLite через `sqlite-data` (Point-Free).

### 2. AgentLogsSDK (встраивается в приложение)
- Перехватывает HTTP-трафик через `URLProtocol`
- Перехватывает `stdout`/`stderr` через `dup2()` + `Pipe`
- Читает `OSLog` через `OSLogStore` (macOS 12+ / iOS 15+)
- Предоставляет API для кастомных логов
- Пишет всё в локальный SQLite
- Каждый запуск приложения = новая сессия с уникальным ID
- На физическом устройстве поднимает HTTP-сервер (Swift NIO) + Bonjour

### 3. AgentLogsCLI (executable, запускается на Mac)
- Читает SQLite базу напрямую (симулятор) или по сети (устройство через Bonjour)
- Claude Code вызывает через Bash, руководствуясь Skill
- Три режима вывода: human-readable, `--json`, `--toon` (token-optimized)

### Flow

```
App → SQLite ← CLI ← Claude Code (через Bash + Skill)
App (device) → HTTP/Bonjour → CLI ← Claude Code
```

## Структура данных (sqlite-data)

### Session

```swift
@Table
struct Session: Identifiable {
    let id: UUID
    var appName: String
    var appVersion: String?
    var bundleID: String?
    var osName: String          // "iOS" / "macOS"
    var osVersion: String
    var deviceModel: String
    var startedAt: Date
    var endedAt: Date?
    var isCrashed: Bool = false
}
```

### LogEntry

```swift
@Table
struct LogEntry: Identifiable {
    let id: Int                 // AUTOINCREMENT
    var sessionID: Session.ID
    var timestamp: Date
    var category: LogCategory   // .http, .system, .oslog, .custom
    var level: LogType          // .debug, .info, .warning, .error, .critical
    var message: String
    var metadata: String?       // JSON blob
    var sourceFile: String?
    var sourceLine: Int?
}
```

### HTTPEntry

```swift
@Table
struct HTTPEntry: Identifiable {
    @Column(primaryKey: true)
    let logEntryID: LogEntry.ID
    var method: String
    var url: String
    var requestHeaders: String? // JSON
    var requestBody: String?
    var statusCode: Int?
    var responseHeaders: String? // JSON
    var responseBody: String?
    var durationMs: Double?
}
```

Индексы по `sessionID`, `timestamp`, `category`, `level`.

## SDK — внутренняя архитектура

### Точка входа

```swift
AgentLogs.start(
    config: .init(
        enableHTTPCapture: true,
        enableSystemLogCapture: true,
        enableOSLogCapture: true,
        logLevel: .debug,
        databasePath: nil
    )
)
```

### Публичный API — один метод

```swift
public enum LogType {
    case debug, info, warning, error, critical
}

AgentLogs.log("message", type: .info, file: #file, line: #line)

// type по умолчанию .info, file и line подставляются автоматически:
AgentLogs.log("Loaded \(items.count) items")
```

### Три коллектора

- **HTTPCollector** — кастомный `URLProtocol`, перехватывает request/response, пишет `LogEntry` + `HTTPEntry`
- **SystemLogCollector** — перенаправляет `stdout`/`stderr` через `dup2()` + `Pipe`, пишет `LogEntry` с категорией `.system`
- **OSLogCollector** — polling `OSLogStore`, фильтрация по `bundleIdentifier`, пишет `LogEntry` с категорией `.oslog`

### Батчинг

Внутренний буфер копит записи и сбрасывает в SQLite пачкой — по таймеру (каждые 500ms) или при достижении лимита (50 записей).

### Завершение сессии

- `applicationWillTerminate` / `sceneDidDisconnect` — flush буфера, проставляем `endedAt`
- Крэш — `NSSetUncaughtExceptionHandler`, помечаем `isCrashed = true`

### Conditional compilation

```swift
#if DEBUG || AGENTLOGS_ENABLED
// вся логика активна
#else
// все методы — пустые no-op
#endif
```

## Поддержка физического устройства

SDK автоматически определяет среду:

- **Симулятор** — только запись в SQLite, CLI читает файл с диска
- **Физическое устройство** — запись в SQLite + HTTP-сервер на Swift NIO, публикация через Bonjour (`_agentlogs._tcp`)

### HTTP API на устройстве

```
POST /logs/query     — запрос логов с фильтрами
POST /logs/tail      — инкрементальные обновления
GET  /sessions       — список сессий
GET  /http/:id       — детали HTTP-запроса
```

### CLI — два транспорта

```swift
protocol LogDataSource {
    func fetchSessions(...) async throws -> [Session]
    func fetchLogs(...) async throws -> [LogEntry]
    func tailLogs(...) async throws -> [LogEntry]
}

class SQLiteDataSource: LogDataSource { ... }   // симулятор
class NetworkDataSource: LogDataSource { ... }  // устройство
```

CLI при старте ищет SQLite базы симуляторов на диске + слушает Bonjour для устройств.

## CLI — команды

```bash
# Сессии
agent-logs sessions
agent-logs sessions --crashed

# Логи
agent-logs logs <session-id>
agent-logs logs <session-id> --level error
agent-logs logs <session-id> --category http
agent-logs logs latest

# Real-time
agent-logs tail
agent-logs tail <session-id> --after <id>

# HTTP детали
agent-logs http <log-entry-id>

# Поиск
agent-logs search "timeout" --session <id>
agent-logs search "500" --category http

# Устройства
agent-logs devices
agent-logs logs <session-id> --device <name>
```

## Три режима вывода

### Human-readable (по умолчанию)

```
[14:32:01] ERROR [HTTPCollector] POST /api/users -> 500 (234ms)
[14:32:01] ERROR [Custom] Failed to parse user response
           metadata: {"raw": "<!DOCTYPE html>..."}
           at UserService.swift:42
```

### JSON (`--json`)

Полный JSON для скриптов и интеграций.

### Token-optimized (`--toon`)

```
14:32:01|ERR|http|POST /api/users->500 234ms
14:32:01|ERR|cst|Parse fail@UserService.swift:42
```

Особенности `--toon`:
- Убирает декоративные символы и отступы
- Сокращает level: `ERR`, `WRN`, `INF`, `DBG`, `CRT`
- Сокращает category: `http`, `sys`, `osl`, `cst`
- Одна строка на запись, `|` как разделитель
- HTTP: метод + path (без хоста) + статус + duration
- Обрезает длинные messages до 120 символов
- metadata только ключи (полные данные через `agent-logs http <id>`)

## Skill

Файл `.claude/skills/agent-logs.md` описывает агенту как использовать CLI:

```markdown
Когда пользователь просит помочь с дебагом, найти ошибку,
или разобраться что произошло в приложении — используй CLI `agent-logs`.

ВАЖНО: всегда добавляй флаг --toon для экономии токенов.
Используй полный вывод или --json только когда нужны детали
конкретной записи (agent-logs http <id>).

Начни с `agent-logs sessions` чтобы увидеть доступные сессии.
Затем `agent-logs logs latest --level error --toon` для быстрого обзора проблем.
Для real-time отслеживания используй `agent-logs tail --toon`.
```

## Структура Swift Package

```
AgentLogs/
├── Package.swift
├── Sources/
│   ├── AgentLogsCore/
│   │   ├── Models/
│   │   │   ├── Session.swift
│   │   │   ├── LogEntry.swift
│   │   │   ├── HTTPEntry.swift
│   │   │   ├── LogType.swift
│   │   │   └── LogCategory.swift
│   │   ├── Database/
│   │   │   ├── DatabaseSetup.swift
│   │   │   └── DatabasePath.swift
│   │   └── Queries/
│   │       └── LogQueries.swift
│   │
│   ├── AgentLogsSDK/
│   │   ├── AgentLogs.swift
│   │   ├── Configuration.swift
│   │   ├── SessionManager.swift
│   │   ├── LogBuffer.swift
│   │   ├── Collectors/
│   │   │   ├── HTTPCollector.swift
│   │   │   ├── SystemLogCollector.swift
│   │   │   └── OSLogCollector.swift
│   │   └── Server/
│   │       ├── BonjourServer.swift
│   │       └── BonjourAdvertiser.swift
│   │
│   └── AgentLogsCLI/
│       ├── main.swift
│       ├── Commands/
│       │   ├── SessionsCommand.swift
│       │   ├── LogsCommand.swift
│       │   ├── TailCommand.swift
│       │   ├── HTTPCommand.swift
│       │   ├── SearchCommand.swift
│       │   └── DevicesCommand.swift
│       ├── DataSources/
│       │   ├── LogDataSource.swift
│       │   ├── SQLiteDataSource.swift
│       │   └── NetworkDataSource.swift
│       ├── Discovery/
│       │   ├── SimulatorDiscovery.swift
│       │   └── BonjourDiscovery.swift
│       └── Formatters/
│           ├── HumanFormatter.swift
│           ├── JSONFormatter.swift
│           └── ToonFormatter.swift
│
├── Tests/
│   ├── AgentLogsCoreTests/
│   ├── AgentLogsSDKTests/
│   └── AgentLogsCLITests/
│
└── docs/
    └── plans/
```

### Зависимости

- `AgentLogsCore` → `sqlite-data` (Point-Free)
- `AgentLogsSDK` → `AgentLogsCore`, `swift-nio` (Apple)
- `AgentLogsCLI` → `AgentLogsCore`, `swift-argument-parser` (Apple)
