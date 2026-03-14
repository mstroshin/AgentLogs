# AgentLogs — Tasks

## Phase 1: Фундамент
- [ ] Package.swift с тремя таргетами и зависимостями
- [ ] Модели данных: Session, LogEntry, HTTPEntry, LogType, LogCategory
- [ ] DatabaseSetup: миграции, создание DatabaseQueue
- [ ] DatabasePath: определение пути к SQLite (симулятор / устройство)

## Phase 2: SDK — сбор логов
- [ ] AgentLogs.swift: публичный API — `start()`, `log()`
- [ ] Configuration.swift
- [ ] SessionManager: создание/завершение сессии, крэш-хендлинг
- [ ] LogBuffer: батчинг записей (500ms / 50 записей)
- [ ] HTTPCollector: URLProtocol перехват
- [ ] SystemLogCollector: stdout/stderr через dup2
- [ ] OSLogCollector: OSLogStore polling

## Phase 3: CLI — базовые команды
- [ ] main.swift + swift-argument-parser
- [ ] LogDataSource протокол
- [ ] SQLiteDataSource: чтение базы с диска
- [ ] SimulatorDiscovery: поиск SQLite баз симуляторов
- [ ] SessionsCommand
- [ ] LogsCommand
- [ ] TailCommand
- [ ] HTTPCommand
- [ ] SearchCommand
- [ ] Форматтеры: HumanFormatter, JSONFormatter, ToonFormatter

## Phase 4: Физическое устройство
- [ ] BonjourServer: Swift NIO HTTP-сервер в SDK
- [ ] BonjourAdvertiser: анонс через NetService
- [ ] NetworkDataSource: HTTP-клиент в CLI
- [ ] BonjourDiscovery: обнаружение устройств
- [ ] DevicesCommand

## Phase 5: Интеграция с Claude Code
- [ ] Skill файл: .claude/skills/agent-logs.md
- [ ] Документация по установке и настройке

## Phase 6: Тесты
- [ ] AgentLogsCoreTests: модели, миграции, запросы
- [ ] AgentLogsSDKTests: коллекторы, буфер, сессии
- [ ] AgentLogsCLITests: команды, форматтеры
