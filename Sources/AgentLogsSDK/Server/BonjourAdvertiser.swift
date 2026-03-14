import Foundation

/// Advertises the AgentLogs HTTP server via Bonjour so desktop tools can discover it.
final class BonjourAdvertiser: NSObject, @unchecked Sendable, NetServiceDelegate {
    private var netService: NetService?
    private let port: Int
    private let sessionID: String
    private let bundleID: String
    private let lock = NSLock()

    init(port: Int, sessionID: String, bundleID: String) {
        self.port = port
        self.sessionID = sessionID
        self.bundleID = bundleID
        super.init()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        let serviceName = "AgentLogs-\(bundleID)"
        let service = NetService(
            domain: "",
            type: "_agentlogs._tcp.",
            name: serviceName,
            port: Int32(port)
        )

        let txtData = NetService.data(fromTXTRecord: [
            "bundleID": bundleID.data(using: .utf8) ?? Data(),
            "sessionID": sessionID.data(using: .utf8) ?? Data(),
        ])
        service.setTXTRecord(txtData)
        service.delegate = self
        service.publish()
        netService = service
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        netService?.stop()
        netService = nil
    }

    // MARK: - NetServiceDelegate

    func netServiceDidPublish(_ sender: NetService) {
        // Successfully advertised
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        // Failed to advertise — non-fatal
    }
}
