#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore

struct LogDetailView: View {
    let entry: LogEntry
    @ObservedObject var viewModel: LogListViewModel
    @State private var httpEntry: HTTPEntry?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        List {
            Section("Info") {
                DetailRow(label: "Timestamp", value: Self.dateFormatter.string(from: entry.timestamp))
                DetailRow(label: "Level", value: entry.level.rawValue.uppercased(), color: Theme.color(for: entry.level))
                DetailRow(label: "Category", value: entry.category.rawValue)
                DetailRow(label: "ID", value: "\(entry.id)")
            }

            Section("Message") {
                Text(entry.message)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            if let metadata = entry.metadata, !metadata.isEmpty {
                Section("Metadata") {
                    Text(metadata)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let file = entry.sourceFile {
                Section("Source") {
                    let line = entry.sourceLine.map { ":\($0)" } ?? ""
                    Text("\(file)\(line)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            if entry.category == .http {
                Section {
                    if let httpEntry {
                        NavigationLink("HTTP Details") {
                            HTTPDetailView(entry: httpEntry)
                        }
                    } else {
                        Button("Load HTTP Details") {
                            httpEntry = viewModel.fetchHTTPEntry(logEntryID: entry.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Log Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entry.category == .http {
                httpEntry = viewModel.fetchHTTPEntry(logEntryID: entry.id)
            }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(color != .primary ? .semibold : .regular)
        }
    }
}
#endif
