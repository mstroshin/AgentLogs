#if canImport(SwiftUI) && os(iOS)
import Foundation
import CoreData
import Combine
import AgentLogsCore
import AgentLogsSDK

@MainActor
final class LogListViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: LogCategory?
    @Published var selectedLevel: LogLevel?
    @Published var isLoading = false

    private var context: NSManagedObjectContext?
    private var sessionID: UUID?
    private var lastSeenID: Int = 0
    private var pollTimer: Timer?
    private var searchDebounce: AnyCancellable?

    init() {}

    /// Internal init for testing — injects context and sessionID directly.
    init(context: NSManagedObjectContext, sessionID: UUID) {
        self.context = context
        self.sessionID = sessionID
    }

    func start() async {
        guard context == nil else {
            // Already initialized (test injection)
            reload()
            startPolling()
            return
        }

        guard let ui = await AgentLogs.uiContext() else { return }
        self.context = ui.context
        self.sessionID = ui.sessionID

        reload()
        startPolling()
        observeSearchText()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        searchDebounce?.cancel()
    }

    func reload() {
        guard let context, let sessionID else { return }

        do {
            if searchText.isEmpty {
                logs = try context.performAndWait {
                    try LogQueries.fetchLogs(
                        context: context,
                        sessionID: sessionID,
                        category: selectedCategory,
                        level: selectedLevel,
                        limit: 1000
                    )
                }
            } else {
                logs = try context.performAndWait {
                    try LogQueries.searchLogs(
                        context: context,
                        query: searchText,
                        sessionID: sessionID,
                        category: selectedCategory,
                        level: selectedLevel,
                        limit: 500
                    )
                }
            }
            lastSeenID = logs.last?.id ?? 0
        } catch {
            // Silently handle — UI should not crash
        }
    }

    func fetchHTTPEntry(logEntryID: Int) -> HTTPEntry? {
        guard let context else { return nil }
        return try? context.performAndWait {
            try LogQueries.fetchHTTPEntry(context: context, logEntryID: logEntryID)
        }
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
        guard let context, let sessionID, searchText.isEmpty else { return }

        context.refreshAllObjects()

        do {
            let newEntries = try context.performAndWait {
                try LogQueries.tailLogs(
                    context: context,
                    sessionID: sessionID,
                    afterID: lastSeenID
                )
            }
            if !newEntries.isEmpty {
                // Apply current filters
                let filtered: [LogEntry]
                if selectedCategory != nil || selectedLevel != nil {
                    filtered = newEntries.filter { entry in
                        if let cat = selectedCategory, entry.category != cat { return false }
                        if let lvl = selectedLevel, entry.level != lvl { return false }
                        return true
                    }
                } else {
                    filtered = newEntries
                }
                logs.append(contentsOf: filtered)
                lastSeenID = newEntries.last?.id ?? lastSeenID
            }
        } catch {
            // Silently handle
        }
    }

    private func observeSearchText() {
        searchDebounce = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reload()
            }

        // Also observe filter changes
        $selectedCategory
            .dropFirst()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        $selectedLevel
            .dropFirst()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
#endif
