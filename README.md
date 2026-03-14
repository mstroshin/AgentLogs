# AgentLogs

Swift-библиотека для сбора логов iOS/macOS приложений с доступом через CLI для Claude Code.

## Что это

AgentLogs автоматически собирает HTTP-трафик, системные логи (`print`, `os_log`) и кастомные сообщения в SQLite базу. CLI-утилита `agent-logs` позволяет Claude Code читать эти логи и помогать в дебаге.

## Требования

- iOS 15+ / macOS 12+
- Swift 6.1+
- Xcode 16+

## Установка

### Swift Package Manager

Добавьте в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-repo/AgentLogs", from: "1.0.0"),
]
```

Подключите SDK к таргету приложения:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AgentLogsSDK", package: "AgentLogs"),
    ]
)
```

## Быстрый старт

### 1. Подключите SDK в приложении

```swift
import AgentLogsSDK

// При запуске приложения
AgentLogs.start()

// Логирование
AgentLogs.log("User tapped login button")
AgentLogs.log("Failed to load profile", type: .error)
AgentLogs.log("Cache miss", type: .warning, file: #file, line: #line)

// При завершении (опционально — SDK обрабатывает завершение автоматически)
AgentLogs.stop()
```

### 2. Установите CLI

```bash
# Из корня репозитория
swift build -c release --product agent-logs

# Скопируйте в PATH
cp .build/release/agent-logs /usr/local/bin/
```

### 3. Настройте Claude Code Skill

Скопируйте файл `.claude/skills/agent-logs.md` в ваш проект. Claude Code будет автоматически использовать CLI при дебаге.

## SDK

### Конфигурация

```swift
AgentLogs.start(config: .init(
    enableHTTPCapture: true,       // Перехват URLSession запросов
    enableSystemLogCapture: true,  // Перехват stdout/stderr (print)
    enableOSLogCapture: true,      // Чтение OSLog
    logLevel: .debug,              // Минимальный уровень логирования
    databasePath: nil              // nil = стандартный путь
))
```

### API

Один метод для всех логов:

```swift
AgentLogs.log(_ message: String, type: LogLevel = .info, file: String = #file, line: Int = #line)
```

Уровни: `.debug`, `.info`, `.warning`, `.error`, `.critical`

### Что собирается автоматически

| Категория | Источник | Как работает |
|-----------|----------|--------------|
| `http` | URLSession | URLProtocol перехватывает все запросы |
| `system` | print() | dup2 + Pipe перенаправляет stdout/stderr |
| `oslog` | os_log | Polling OSLogStore каждые 2 секунды |
| `custom` | AgentLogs.log() | Прямой вызов API |

### Conditional compilation

SDK активен только в Debug-сборках. Для включения в Release добавьте флаг:

```swift
// В Build Settings → Swift Compiler - Custom Flags
-D AGENTLOGS_ENABLED
```

### Физическое устройство

На физическом устройстве SDK автоматически поднимает HTTP-сервер и публикует его через Bonjour (`_agentlogs._tcp`). CLI обнаруживает устройство по сети.

## CLI

### Команды

```bash
# Список сессий
agent-logs sessions
agent-logs sessions --crashed

# Логи сессии
agent-logs logs latest                       # последняя сессия
agent-logs logs <session-id> --level error   # только ошибки
agent-logs logs <session-id> --category http # только HTTP

# Real-time мониторинг
agent-logs tail
agent-logs tail <session-id>

# Детали HTTP запроса
agent-logs http <log-entry-id>

# Поиск
agent-logs search "timeout"
agent-logs search "500" --category http

# Обнаружение устройств
agent-logs devices
```

### Форматы вывода

**Human-readable** (по умолчанию):
```
[14:32:01] ERROR [HTTP] POST /api/users -> 500 (234ms)
[14:32:01] ERROR [Custom] Failed to parse user response
           at UserService.swift:42
```

**Token-optimized** (`--toon`) — для Claude Code:
```
14:32:01|ERR|http|POST /api/users->500 234ms
14:32:01|ERR|cst|Parse fail@UserService.swift:42
```

**JSON** (`--json`) — для скриптов и интеграций.

### Подключение к базе данных

```bash
# Автоопределение (ищет базы симуляторов)
agent-logs sessions

# Указать путь явно
agent-logs sessions --db-path ~/path/to/agent-logs.sqlite

# Подключение к физическому устройству
agent-logs sessions --remote 192.168.1.42:8080
```

## Архитектура

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
│  (читает SQLite / Bonjour)  │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│       Claude Code           │
│    (через Bash + Skill)     │
└─────────────────────────────┘
```

### Структура пакета

```
Sources/
├── AgentLogsCore/    — модели, БД, запросы (GRDB)
├── AgentLogsSDK/     — SDK для приложения (коллекторы, буфер, Bonjour-сервер)
└── AgentLogsCLI/     — CLI утилита (команды, форматтеры, data sources)
```

## Лицензия

MIT
