#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore
import AgentLogsSDK

/// SwiftUI view that displays logs for the current AgentLogs session.
///
/// Usage:
/// ```swift
/// // Present via the dedicated window (recommended):
/// AgentLogs.showUI()
///
/// // Or as a SwiftUI sheet:
/// .sheet(isPresented: $showLogs) {
///     AgentLogsView()
/// }
/// ```
public struct AgentLogsView: View {
    @StateObject private var viewModel = LogListViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Optional callback used by AgentLogsWindow to dismiss the overlay window.
    private let onDismiss: (() -> Void)?

    public init() {
        self.onDismiss = nil
    }

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                FilterBar(
                    selectedCategory: $viewModel.selectedCategory,
                    selectedLevel: $viewModel.selectedLevel
                )

                Divider()

                LogListView(logs: viewModel.logs, viewModel: viewModel)
            }
            .searchable(text: $viewModel.searchText, prompt: "Search logs...")
            .navigationTitle("AgentLogs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(viewModel.logs.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
#endif
