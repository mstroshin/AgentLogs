#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore

struct FilterBar: View {
    @Binding var selectedCategory: LogCategory?
    @Binding var selectedLevel: LogLevel?

    private let categories: [LogCategory] = [.http, .system, .oslog, .manualLogs]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Level filters
                ForEach(LogLevel.allCases, id: \.rawValue) { level in
                    FilterPill(
                        title: level.rawValue.uppercased(),
                        color: Theme.color(for: level),
                        isSelected: selectedLevel == level
                    ) {
                        selectedLevel = selectedLevel == level ? nil : level
                    }
                }

                Divider().frame(height: 20)

                // Category filters
                ForEach(categories, id: \.rawValue) { category in
                    FilterPill(
                        title: category.rawValue,
                        color: .secondary,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct FilterPill: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.2) : Color.clear)
                .foregroundColor(isSelected ? color : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? color : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
#endif
