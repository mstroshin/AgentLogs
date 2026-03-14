import Foundation
import GRDB

public enum LogLevel: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case debug
    case info
    case warning
    case error
    case critical
}
