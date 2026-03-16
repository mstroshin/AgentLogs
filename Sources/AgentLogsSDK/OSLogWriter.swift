#if canImport(OSLog)
import OSLog
import AgentLogsCore

struct OSLogWriter: Sendable {
    private let logger: os.Logger

    init(subsystem: String, category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    func write(_ message: String, level: LogLevel) {
        switch level {
        case .debug:    logger.debug("\(message, privacy: .public)")
        case .info:     logger.info("\(message, privacy: .public)")
        case .warning:  logger.warning("\(message, privacy: .public)")
        case .error:    logger.error("\(message, privacy: .public)")
        case .critical: logger.fault("\(message, privacy: .public)")
        }
    }
}
#endif
