#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore

struct HTTPDetailView: View {
    let entry: HTTPEntry

    var body: some View {
        List {
            Section("Request") {
                HStack {
                    Text(entry.method)
                        .font(.headline.monospaced())
                    if let status = entry.statusCode {
                        Spacer()
                        Text("\(status)")
                            .font(.headline.monospaced())
                            .foregroundColor(statusColor(status))
                    }
                }

                Text(entry.url)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)

                if let headers = entry.requestHeaders, !headers.isEmpty {
                    DisclosureGroup("Request Headers") {
                        Text(formatJSON(headers))
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let body = entry.requestBody, !body.isEmpty {
                    DisclosureGroup("Request Body") {
                        Text(formatJSON(body))
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Response") {
                if let headers = entry.responseHeaders, !headers.isEmpty {
                    DisclosureGroup("Response Headers") {
                        Text(formatJSON(headers))
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let body = entry.responseBody, !body.isEmpty {
                    DisclosureGroup("Response Body") {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(formatJSON(body))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let duration = entry.durationMs {
                Section("Performance") {
                    HStack {
                        Text("Duration")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f ms", duration))
                            .font(.body.monospaced())
                    }
                }
            }
        }
        .navigationTitle("\(entry.method) \(statusText)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        entry.statusCode.map { "\($0)" } ?? ""
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        default: return .red
        }
    }

    private func formatJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8)
        else { return string }
        return result
    }
}
#endif
