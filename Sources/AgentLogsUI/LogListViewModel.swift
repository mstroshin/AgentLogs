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

    private var context: NSManagedObjectContext?
    private var sessionID: UUID?
    private var lastSeenID: Int = 0
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {}

    /// Internal init for testing.
    init(context: NSManagedObjectContext, sessionID: UUID) {
        self.context = context
        self.sessionID = sessionID
    }

    func start() async {
        if context == nil {
            guard let ui = await AgentLogs.uiContext() else { return }
            self.context = ui.context
            self.sessionID = ui.sessionID
        }

        reload()
        startPolling()
        setupObservers()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
    }

    func reload() {
        guard let context, let sessionID else { return }

        context.refreshAllObjects()

        do {
            if searchText.isEmpty {
                logs = try context.performAndWait {
                    try LogQueries.fetchLogs(
                        context: context,
                        sessionID: sessionID,
                        category: selectedCategory,
                        level: selectedLevel,
                        limit: 1000
                    ).reversed()
                }
            } else {
                // searchLogs already returns DESC order
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
            lastSeenID = logs.first?.id ?? 0
        } catch {
            // UI should not crash
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
        // During search or with filters, just do a full reload to stay consistent
        guard let context, let sessionID, searchText.isEmpty,
              selectedCategory == nil, selectedLevel == nil else {
            return
        }

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
                // New entries at the top (reversed to get newest first)
                logs.insert(contentsOf: newEntries.reversed(), at: 0)
                lastSeenID = newEntries.last?.id ?? lastSeenID
            }
        } catch {
            // Silently handle
        }
    }

    private func setupObservers() {
        // Cancel any previous observers
        cancellables.removeAll()

        // Debounced search → full reload
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .dropFirst() // skip initial value
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        // Filter changes → full reload
        $selectedCategory
            .dropFirst()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        $selectedLevel
            .dropFirst()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }
}
#endif
