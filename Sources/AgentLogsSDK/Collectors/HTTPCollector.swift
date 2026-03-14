import Foundation
import AgentLogsCore

/// URLProtocol subclass that intercepts HTTP requests for logging.
final class AgentLogsURLProtocol: URLProtocol, @unchecked Sendable {
    // Protected by a lock because URLProtocol is not Sendable but we need
    // static mutable state for the collector reference.
    private static let collectorLock = NSLock()
    private static nonisolated(unsafe) var _collector: HTTPCollector?

    static var collector: HTTPCollector? {
        get {
            collectorLock.lock()
            defer { collectorLock.unlock() }
            return _collector
        }
        set {
            collectorLock.lock()
            defer { collectorLock.unlock() }
            _collector = newValue
        }
    }

    private static let handledKey = "com.agentlogs.handled"
    private var dataTask: URLSessionDataTask?
    private var receivedData = Data()
    private var response: URLResponse?
    private var startTime: Date?

    // Lazy session that bypasses this protocol to avoid infinite recursion
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Remove our protocol from the chain to avoid recursion
        config.protocolClasses = config.protocolClasses?.filter { $0 !== AgentLogsURLProtocol.self }
        return URLSession(configuration: config)
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        startTime = Date()

        let finalRequest = mutableRequest as URLRequest
        dataTask = Self.urlSession.dataTask(with: finalRequest) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                self.logHTTPExchange(request: finalRequest, data: nil, response: nil, error: error)
                return
            }

            if let response {
                self.response = response
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data {
                self.receivedData = data
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
            self.logHTTPExchange(request: finalRequest, data: data, response: response, error: nil)
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }

    private func logHTTPExchange(
        request: URLRequest,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) {
        guard let collector = Self.collector else { return }

        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "unknown"

        let requestHeaders: String? = {
            guard let headers = request.allHTTPHeaderFields, !headers.isEmpty else { return nil }
            return (try? JSONSerialization.data(withJSONObject: headers)).flatMap { String(data: $0, encoding: .utf8) }
        }()

        let requestBody: String? = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        let statusCode: Int? = (response as? HTTPURLResponse)?.statusCode

        let responseHeaders: String? = {
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            let headers = httpResponse.allHeaderFields
            guard !headers.isEmpty else { return nil }
            // Convert to [String: String] for JSON serialization
            var stringHeaders: [String: String] = [:]
            for (key, value) in headers {
                stringHeaders["\(key)"] = "\(value)"
            }
            return (try? JSONSerialization.data(withJSONObject: stringHeaders)).flatMap { String(data: $0, encoding: .utf8) }
        }()

        let responseBody: String? = data.flatMap { String(data: $0, encoding: .utf8) }

        let durationMs: Double? = startTime.map { Date().timeIntervalSince($0) * 1000.0 }

        let level: LogLevel = {
            if let code = statusCode {
                if code >= 500 { return .error }
                if code >= 400 { return .warning }
            }
            if error != nil { return .error }
            return .info
        }()

        let message: String = {
            if let statusCode {
                return "\(method) \(url) → \(statusCode)"
            } else if let error {
                return "\(method) \(url) → ERROR: \(error.localizedDescription)"
            }
            return "\(method) \(url)"
        }()

        let httpEntry = PendingHTTPEntry(
            method: method,
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            durationMs: durationMs
        )

        collector.log(message: message, level: level, httpEntry: httpEntry)
    }
}

/// Manages HTTP interception lifecycle.
final class HTTPCollector: Sendable {
    private let buffer: LogBuffer
    private let sessionID: UUID

    init(buffer: LogBuffer, sessionID: UUID) {
        self.buffer = buffer
        self.sessionID = sessionID
    }

    func start() {
        AgentLogsURLProtocol.collector = self
        URLProtocol.registerClass(AgentLogsURLProtocol.self)
    }

    func stop() {
        URLProtocol.unregisterClass(AgentLogsURLProtocol.self)
        AgentLogsURLProtocol.collector = nil
    }

    func log(message: String, level: LogLevel, httpEntry: PendingHTTPEntry) {
        let entry = PendingLogEntry(
            sessionID: sessionID,
            timestamp: Date(),
            category: .http,
            level: level,
            message: message,
            httpEntry: httpEntry
        )
        Task {
            await buffer.append(entry)
        }
    }
}
