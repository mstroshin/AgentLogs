import Foundation

public enum DatabasePath: Sendable {
    public static func defaultPath(bundleID: String? = nil) -> String {
        let id = bundleID ?? Bundle.main.bundleIdentifier ?? "com.agentlogs.default"

        #if os(macOS)
        guard let baseDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return NSTemporaryDirectory() + "/\(id)/agent-logs.sqlite"
        }
        let base = baseDir.appendingPathComponent(id)
        #else
        guard let baseDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return NSTemporaryDirectory() + "/AgentLogs/agent-logs.sqlite"
        }
        let base = baseDir.appendingPathComponent("AgentLogs")
        #endif

        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )

        return base.appendingPathComponent("agent-logs.sqlite").path
    }

    #if os(macOS)
    public static func simulatorDatabasePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let devicesDir = home
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices")

        guard let deviceDirs = try? FileManager.default.contentsOfDirectory(
            at: devicesDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var paths: [String] = []
        for deviceDir in deviceDirs {
            let dataDir = deviceDir.appendingPathComponent("data")
            let documentsPattern = dataDir
                .appendingPathComponent("Containers/Data/Application")

            guard let appDirs = try? FileManager.default.contentsOfDirectory(
                at: documentsPattern,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for appDir in appDirs {
                let dbPath = appDir
                    .appendingPathComponent("Documents/AgentLogs/agent-logs.sqlite")
                if FileManager.default.fileExists(atPath: dbPath.path) {
                    paths.append(dbPath.path)
                }
            }
        }

        return paths
    }
    #endif
}
