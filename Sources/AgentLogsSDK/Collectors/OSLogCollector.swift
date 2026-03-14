import Foundation
import AgentLogsCore

#if canImport(OSLog)
import OSLog
#endif

/// Periodically reads OSLog entries and writes them to the log buffer.
final class OSLogCollector: @unchecked Sendable {
    private let buffer: LogBuffer
    private let sessionID: UUID
    private let bundleIdentifier: String
    private var pollTask: Task<Void, Never>?
    private var lastPosition: Date
    private let lock = NSLock()

    #if canImport(OSLog)
    private var logStore: OSLogStore?
    #endif

    init(buffer: LogBuffer, sessionID: UUID) {
        self.buffer = buffer
        self.sessionID = sessionID
        self.bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        self.lastPosition = Date()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard pollTask == nil else { return }

        #if canImport(OSLog)
        if #available(iOS 15.0, macOS 12.0, *) {
            logStore = try? OSLogStore(scope: .currentProcessIdentifier)
        }
        #endif

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.poll()
            }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        pollTask?.cancel()
        pollTask = nil
        #if canImport(OSLog)
        logStore = nil
        #endif
    }

    // MARK: - Lock-protected accessors (synchronous, safe to call from async code)

    #if canImport(OSLog)
    @available(iOS 15.0, macOS 12.0, *)
    private func getStoreAndPosition() -> (OSLogStore, Date)? {
        lock.lock()
        defer { lock.unlock() }
        guard let store = logStore else { return nil }
        return (store, lastPosition)
    }
    #endif

    private func updateLastPosition(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        if date > lastPosition {
            lastPosition = date
        }
    }

    private func poll() async {
        #if canImport(OSLog)
        guard #available(iOS 15.0, macOS 12.0, *) else { return }

        guard let (store, currentLastPosition) = getStoreAndPosition() else { return }

        do {
            let position = store.position(date: currentLastPosition)
            let predicate = NSPredicate(format: "subsystem == %@", bundleIdentifier)

            let entries = try store.getEntries(at: position, matching: predicate)
            var latestDate = currentLastPosition

            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                let entryDate = logEntry.date
                // Skip entries we've already seen
                guard entryDate > currentLastPosition else { continue }
                if entryDate > latestDate {
                    latestDate = entryDate
                }

                let level: LogLevel = {
                    switch logEntry.level {
                    case .debug: return .debug
                    case .info: return .info
                    case .notice: return .info
                    case .error: return .error
                    case .fault: return .critical
                    default: return .info
                    }
                }()

                let pending = PendingLogEntry(
                    sessionID: sessionID,
                    timestamp: entryDate,
                    category: .oslog,
                    level: level,
                    message: logEntry.composedMessage,
                    metadata: logEntry.category.isEmpty ? nil : logEntry.category
                )
                await buffer.append(pending)
            }

            if latestDate > currentLastPosition {
                updateLastPosition(latestDate)
            }
        } catch {
            // OSLogStore can fail on some platforms/sandboxes — silently ignore
        }
        #endif
    }

    deinit {
        pollTask?.cancel()
    }
}
