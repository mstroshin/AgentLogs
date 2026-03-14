import Foundation
import AgentLogsCore

struct SimulatorDatabase: Sendable {
    let path: String
    let deviceUDID: String
    let modifiedAt: Date
}

enum SimulatorDiscovery: Sendable {
    static func discoverDatabases() -> [SimulatorDatabase] {
        let paths = DatabasePath.simulatorDatabasePaths()
        let fm = FileManager.default

        return paths.compactMap { path in
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date else {
                return nil
            }

            // Extract device UDID from path
            // Path format: .../CoreSimulator/Devices/<UDID>/data/Containers/...
            let components = path.components(separatedBy: "/")
            let devicesIndex = components.firstIndex(of: "Devices")
            let udid: String
            if let idx = devicesIndex, idx + 1 < components.count {
                udid = components[idx + 1]
            } else {
                udid = "unknown"
            }

            return SimulatorDatabase(path: path, deviceUDID: udid, modifiedAt: modified)
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func mostRecentDatabase() -> SimulatorDatabase? {
        discoverDatabases().first
    }
}
