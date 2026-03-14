#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore
import AgentLogsSDK

/// SwiftUI view that displays logs for the current AgentLogs session.
///
/// Usage:
/// ```swift
/// // Present directly:
/// .sheet(isPresented: $showLogs) {
///     AgentLogsView()
/// }
///
/// // Or use the SDK convenience method from anywhere:
/// AgentLogs.showUI()
/// ```
public struct AgentLogsView: View {
    @StateObject private var viewModel = LogListViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

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
                    Button("Close") { dismiss() }
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
