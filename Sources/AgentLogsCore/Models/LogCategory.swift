import Foundation
import GRDB

public enum LogCategory: String, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case http
    case system
    case oslog
    case custom
}
