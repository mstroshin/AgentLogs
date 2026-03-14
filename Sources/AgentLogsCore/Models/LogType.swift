import Foundation

public enum LogLevel: String, Sendable, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case critical
}
