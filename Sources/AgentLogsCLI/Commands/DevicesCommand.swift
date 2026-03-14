import ArgumentParser
import Foundation
import AgentLogsCore

struct Devices: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "Discover available devices and simulator databases."
    )

    @Flag(name: .long, help: "Also scan for Bonjour devices on the network.")
    var network: Bool = false

    func run() throws {
        // Simulator databases
        let simulatorDBs = SimulatorDiscovery.discoverDatabases()

        print("=== Simulator Databases ===")
        if simulatorDBs.isEmpty {
            print("  No simulator databases found.")
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            for db in simulatorDBs {
                print("  Device: \(db.deviceUDID)")
                print("  Path:   \(db.path)")
                print("  Modified: \(dateFormatter.string(from: db.modifiedAt))")
                print()
            }
        }

        // Network devices (Bonjour)
        if network {
            print("=== Network Devices ===")
            print("Scanning for Bonjour devices (3 seconds)...")
            let discovery = BonjourDiscovery(timeout: 3.0)
            let devices = discovery.discover()

            if devices.isEmpty {
                print("  No network devices found.")
            } else {
                for device in devices {
                    print("  \(device.name) - \(device.host):\(device.port)")
                }
            }
        }
    }
}
