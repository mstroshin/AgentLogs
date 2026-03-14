import Foundation
import AgentLogsCore

struct NetworkDataSource: LogDataSource, Sendable {
    let baseURL: URL

    init(host: String, port: Int) throws {
        guard let url = URL(string: "http://\(host):\(port)") else {
            throw NetworkError.invalidURL("http://\(host):\(port)")
        }
        self.baseURL = url
    }

    func fetchSessions(crashedOnly: Bool, limit: Int) throws -> [Session] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/sessions"), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.appendingPathComponent("/sessions").absoluteString)
        }
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if crashedOnly {
            queryItems.append(URLQueryItem(name: "crashed", value: "true"))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NetworkError.invalidURL(components.description)
        }
        return try performRequest(url: url)
    }

    func fetchLogs(sessionID: UUID, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/sessions/\(sessionID.uuidString)/logs"), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let category { queryItems.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let level { queryItems.append(URLQueryItem(name: "level", value: level.rawValue)) }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NetworkError.invalidURL(components.description)
        }
        return try performRequest(url: url)
    }

    func tailLogs(sessionID: UUID, afterID: Int) throws -> [LogEntry] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/sessions/\(sessionID.uuidString)/tail"), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }
        components.queryItems = [URLQueryItem(name: "after", value: "\(afterID)")]
        guard let url = components.url else {
            throw NetworkError.invalidURL(components.description)
        }
        return try performRequest(url: url)
    }

    func fetchHTTPEntry(logEntryID: Int) throws -> HTTPEntry? {
        let url = baseURL.appendingPathComponent("/logs/\(logEntryID)/http")
        do {
            return try performRequest(url: url, allowNotFound: true) as HTTPEntry
        } catch NetworkError.notFound {
            return nil
        }
    }

    func searchLogs(query: String, sessionID: UUID?, category: LogCategory?, level: LogLevel?, limit: Int) throws -> [LogEntry] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/search"), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let sessionID { queryItems.append(URLQueryItem(name: "session", value: sessionID.uuidString)) }
        if let category { queryItems.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let level { queryItems.append(URLQueryItem(name: "level", value: level.rawValue)) }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NetworkError.invalidURL(components.description)
        }
        return try performRequest(url: url)
    }

    func latestSessionID() throws -> UUID? {
        let url = baseURL.appendingPathComponent("/sessions/latest")
        do {
            let response: LatestSessionResponse = try performRequest(url: url, allowNotFound: true)
            return response.id
        } catch NetworkError.notFound {
            return nil
        }
    }

    // MARK: - Private

    private struct LatestSessionResponse: Decodable, Sendable {
        let id: UUID
    }

    private func performRequest<T: Decodable & Sendable>(url: URL, allowNotFound: Bool = false) throws -> T {
        nonisolated(unsafe) var resultValue: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                resultValue = .failure(error)
                semaphore.signal()
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                resultValue = .failure(NetworkError.noData)
                semaphore.signal()
                return
            }
            if allowNotFound && httpResponse.statusCode == 404 {
                // For optional requests, treat 404 as a decoding failure that the caller handles
                resultValue = .failure(NetworkError.notFound)
                semaphore.signal()
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                resultValue = .failure(NetworkError.httpError(statusCode: httpResponse.statusCode))
                semaphore.signal()
                return
            }
            guard let data else {
                resultValue = .failure(NetworkError.noData)
                semaphore.signal()
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let decoded = try decoder.decode(T.self, from: data)
                resultValue = .success(decoded)
            } catch {
                resultValue = .failure(error)
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        guard let result = resultValue else {
            throw NetworkError.noData
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

enum NetworkError: Error, CustomStringConvertible {
    case noData
    case notFound
    case invalidURL(String)
    case httpError(statusCode: Int)

    var description: String {
        switch self {
        case .noData: return "No data received from server"
        case .notFound: return "Resource not found"
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .httpError(let code): return "HTTP error: \(code)"
        }
    }
}
