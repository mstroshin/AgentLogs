import Foundation

struct DiscoveredDevice: Sendable {
    let name: String
    let host: String
    let port: Int
}

final class BonjourDiscovery: NSObject, @unchecked Sendable {
    private let browser: NetServiceBrowser
    private let delegate: BrowserDelegate
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 3.0) {
        self.browser = NetServiceBrowser()
        self.delegate = BrowserDelegate()
        self.timeout = timeout
        super.init()
        self.browser.delegate = self.delegate
    }

    func discover() -> [DiscoveredDevice] {
        delegate.reset()
        browser.searchForServices(ofType: "_agentlogs._tcp", inDomain: "local.")

        Thread.sleep(forTimeInterval: timeout)
        browser.stop()

        return delegate.resolvedDevices
    }
}

private final class BrowserDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var services: [NetService] = []
    private var _resolvedDevices: [DiscoveredDevice] = []

    var resolvedDevices: [DiscoveredDevice] {
        lock.lock()
        defer { lock.unlock() }
        return _resolvedDevices
    }

    func reset() {
        lock.lock()
        services.removeAll()
        _resolvedDevices.removeAll()
        lock.unlock()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
        services.append(service)
        lock.unlock()

        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        let device = DiscoveredDevice(
            name: sender.name,
            host: hostName,
            port: sender.port
        )

        lock.lock()
        _resolvedDevices.append(device)
        lock.unlock()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // Search failed, nothing to discover
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Resolution failed for this service
    }
}
