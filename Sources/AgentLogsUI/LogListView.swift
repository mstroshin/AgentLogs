#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore

struct LogListView: View {
    let logs: [LogEntry]
    @ObservedObject var viewModel: LogListViewModel

    var body: some View {
        if logs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No logs")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(logs) { entry in
                NavigationLink(destination: LogDetailView(entry: entry, viewModel: viewModel)) {
                    LogRow(entry: entry)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Level badge
            Text(Theme.levelEmoji(for: entry.level))
                .font(.caption2.monospaced().bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Theme.color(for: entry.level))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                // Timestamp + category
                HStack {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Text(entry.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }

                // Message
                Text(entry.message)
                    .font(.footnote)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
