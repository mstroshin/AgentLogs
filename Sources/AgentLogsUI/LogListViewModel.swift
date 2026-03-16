#if canImport(SwiftUI) && os(iOS)
import Foundation
import AgentLogsCore
import AgentLogsSDK

@MainActor
final class LogListViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: LogCategory?
    @Published var selectedLevel: LogLevel?

    private var store: SQLiteStore?
    private var sessionID: UUID?
    private var lastSeenID: Int = 0
    private var pollTimer: Timer?
    private var searchWorkItem: DispatchWorkItem?

    init() {}

    /// Internal init for testing.
    init(store: SQLiteStore, sessionID: UUID) {
        self.store = store
        self.sessionID = sessionID
    }

    func start() async {
        if store == nil {
            guard let ui = await AgentLogs.uiStore() else { return }
            self.store = ui.store
            self.sessionID = ui.sessionID
        }

        reload()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        searchWorkItem?.cancel()
    }

    func reload() {
        guard let store, let sessionID else { return }

        do {
            if searchText.isEmpty {
                logs = try store.fetchLogs(
                    sessionID: sessionID,
                    category: selectedCategory,
                    level: selectedLevel,
                    limit: 1000
                ).reversed()
            } else {
                logs = try store.searchLogs(
                    query: searchText,
                    sessionID: sessionID,
                    category: selectedCategory,
                    level: selectedLevel,
                    limit: 500
                )
            }
            lastSeenID = logs.first?.id ?? 0
        } catch {
            // UI should not crash
        }
    }

    /// Debounced reload for search text changes (300ms delay).
    func debounceReload() {
        searchWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func fetchHTTPEntry(logEntryID: Int) -> HTTPEntry? {
        guard let store else { return nil }
        return try? store.fetchHTTPEntry(logEntryID: logEntryID)
    }

    // MARK: - Private

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollForNewEntries()
            }
        }
    }

    private func pollForNewEntries() {
        // When filters or search are active, do a full reload instead of tail
        guard let store, let sessionID, searchText.isEmpty,
              selectedCategory == nil, selectedLevel == nil else {
            if selectedCategory != nil || selectedLevel != nil || !searchText.isEmpty {
                reload()
            }
            return
        }

        do {
            let newEntries = try store.tailLogs(
                sessionID: sessionID,
                afterID: lastSeenID
            )
            if !newEntries.isEmpty {
                logs.insert(contentsOf: newEntries.reversed(), at: 0)
                lastSeenID = newEntries.last?.id ?? lastSeenID
            }
        } catch {
            // Silently handle
        }
    }
}
#endif
