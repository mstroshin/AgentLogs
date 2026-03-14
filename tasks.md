# AgentLogs — Tasks

## Phase 1: Фундамент
- [x] Package.swift с тремя таргетами и зависимостями
- [x] Модели данных: Session, LogEntry, HTTPEntry, LogLevel, LogCategory
- [x] DatabaseSetup: миграции, создание DatabaseQueue
- [x] DatabasePath: определение пути к SQLite (симулятор / устройство)

## Phase 2: SDK — сбор логов
- [x] AgentLogs.swift: публичный API — `start()`, `log()`
- [x] Configuration.swift
- [x] SessionManager: создание/завершение сессии, крэш-хендлинг
- [x] LogBuffer: батчинг записей (500ms / 50 записей)
- [x] HTTPCollector: URLProtocol перехват
- [x] SystemLogCollector: stdout/stderr через dup2
- [x] OSLogCollector: OSLogStore polling

## Phase 3: CLI — базовые команды
- [x] main.swift + swift-argument-parser
- [x] LogDataSource протокол
- [x] SQLiteDataSource: чтение базы с диска
- [x] SimulatorDiscovery: поиск SQLite баз симуляторов
- [x] SessionsCommand
- [x] LogsCommand
- [x] TailCommand
- [x] HTTPCommand
- [x] SearchCommand
- [x] Форматтеры: HumanFormatter, JSONFormatter, ToonFormatter

## Phase 4: Физическое устройство
- [x] BonjourServer: Swift NIO HTTP-сервер в SDK
- [x] BonjourAdvertiser: анонс через NetService
- [x] NetworkDataSource: HTTP-клиент в CLI
- [x] BonjourDiscovery: обнаружение устройств
- [x] DevicesCommand

## Phase 5: Интеграция с Claude Code
- [x] Skill файл: .claude/skills/agent-logs.md
- [x] Документация по установке и настройке (README.md)

## Phase 6: Тесты
- [x] AgentLogsCoreTests: модели, миграции, запросы (34 теста)
- [x] AgentLogsSDKTests: конфигурация, буфер (9 тестов)
- [x] AgentLogsCLITests: форматтеры (36 тестов)

## Дополнительно
- [x] Исправлен UUID storage: консистентное TEXT хранение вместо BLOB
