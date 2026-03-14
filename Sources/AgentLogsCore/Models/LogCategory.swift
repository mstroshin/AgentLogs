import Foundation

public struct LogCategory: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let http       = LogCategory(rawValue: "http")
    public static let system     = LogCategory(rawValue: "system")
    public static let oslog      = LogCategory(rawValue: "oslog")
    public static let manualLogs = LogCategory(rawValue: "manualLogs")

    // MARK: - Codable (single value, not keyed)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
