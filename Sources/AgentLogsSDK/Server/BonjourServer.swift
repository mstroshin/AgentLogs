import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import GRDB
import AgentLogsCore

/// A lightweight HTTP server using SwiftNIO that serves log data from the local database.
final class BonjourServer: Sendable {
    private let dbQueue: DatabaseQueue
    private let group: EventLoopGroup
    private let lock = NSLock()
    private struct MutableState {
        var channel: Channel?
        var port: Int = 0
    }
    // NSLock-protected mutable state
    private let _state = LockedValue(MutableState())

    var port: Int {
        _state.withLock { $0.port }
    }

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    @discardableResult
    func start() throws -> Int {
        let dbQueue = self.dbQueue
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(dbQueue: dbQueue))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try bootstrap.bind(host: "0.0.0.0", port: 0).wait()
        let boundPort = channel.localAddress?.port ?? 0
        _state.withLock { state in
            state.channel = channel
            state.port = boundPort
        }
        return boundPort
    }

    func stop() {
        let channel = _state.withLock { state -> Channel? in
            let ch = state.channel
            state.channel = nil
            state.port = 0
            return ch
        }
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
    }
}

/// A simple lock-protected value wrapper for Sendable contexts.
private final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

// MARK: - HTTP Handler

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let dbQueue: DatabaseQueue
    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            requestBody = Data()
        case .body(var body):
            if let bytes = body.readBytes(length: body.readableBytes) {
                requestBody.append(contentsOf: bytes)
            }
        case .end:
            guard let head = requestHead else { return }
            handleRequest(context: context, head: head, body: requestBody)
            requestHead = nil
            requestBody = Data()
        }
    }

    private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: Data) {
        let uri = head.uri
        let method = head.method

        do {
            if method == .GET && uri == "/sessions" {
                let sessions = try dbQueue.read { db in
                    try LogQueries.fetchSessions(db: db)
                }
                sendJSON(context: context, value: sessions)
            } else if method == .POST && uri == "/logs/query" {
                let request = try JSONDecoder().decode(LogQueryRequest.self, from: body)
                let logs = try dbQueue.read { db in
                    try LogQueries.fetchLogs(
                        db: db,
                        sessionID: request.sessionID,
                        category: request.category,
                        level: request.level,
                        sinceTimestamp: request.sinceTimestamp,
                        limit: request.limit ?? 500
                    )
                }
                sendJSON(context: context, value: logs)
            } else if method == .POST && uri == "/logs/tail" {
                let request = try JSONDecoder().decode(LogTailRequest.self, from: body)
                let logs = try dbQueue.read { db in
                    try LogQueries.tailLogs(
                        db: db,
                        sessionID: request.sessionID,
                        afterID: request.afterID
                    )
                }
                sendJSON(context: context, value: logs)
            } else if method == .GET && uri.hasPrefix("/http/") {
                let idString = String(uri.dropFirst("/http/".count))
                guard let logEntryID = Int(idString) else {
                    sendError(context: context, status: .badRequest, message: "Invalid ID")
                    return
                }
                let entry = try dbQueue.read { db in
                    try LogQueries.fetchHTTPEntry(db: db, logEntryID: logEntryID)
                }
                if let entry {
                    sendJSON(context: context, value: entry)
                } else {
                    sendError(context: context, status: .notFound, message: "Not found")
                }
            } else {
                sendError(context: context, status: .notFound, message: "Unknown endpoint")
            }
        } catch {
            sendError(context: context, status: .internalServerError, message: error.localizedDescription)
        }
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, data: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(data.count)")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func sendJSON<T: Encodable>(context: ChannelHandlerContext, value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(value)
            sendResponse(context: context, status: .ok, data: data)
        } catch {
            sendError(context: context, status: .internalServerError, message: error.localizedDescription)
        }
    }

    private func sendError(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data("{}".utf8)
        sendResponse(context: context, status: status, data: data)
    }
}

// MARK: - Request Models

private struct LogQueryRequest: Codable, Sendable {
    var sessionID: UUID
    var category: LogCategory?
    var level: LogLevel?
    var sinceTimestamp: Date?
    var limit: Int?
}

private struct LogTailRequest: Codable, Sendable {
    var sessionID: UUID
    var afterID: Int
}
