#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import AgentLogsCore

enum Theme {
    static func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:    return .gray
        case .info:     return .blue
        case .warning:  return .orange
        case .error:    return .red
        case .critical: return .purple
        }
    }

    static func levelEmoji(for level: LogLevel) -> String {
        switch level {
        case .debug:    return "D"
        case .info:     return "I"
        case .warning:  return "W"
        case .error:    return "E"
        case .critical: return "C"
        }
    }

    static func categoryLabel(_ category: LogCategory) -> String {
        category.rawValue
    }
}
#endif
