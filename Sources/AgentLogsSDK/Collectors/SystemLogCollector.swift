#if canImport(Darwin)
import Foundation
import AgentLogsCore

/// Captures stdout and stderr using dup2() + Pipe, preserving original output.
final class SystemLogCollector: @unchecked Sendable {
    private let buffer: LogBuffer
    private let sessionID: UUID

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var isCapturing = false
    private let lock = NSLock()

    init(buffer: LogBuffer, sessionID: UUID) {
        self.buffer = buffer
        self.sessionID = sessionID
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCapturing else { return }
        isCapturing = true

        // Capture stdout
        originalStdout = dup(STDOUT_FILENO)
        let outPipe = Pipe()
        stdoutPipe = outPipe
        dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.handlePipeData(handle: handle, originalFD: self.originalStdout, isError: false)
        }

        // Capture stderr
        originalStderr = dup(STDERR_FILENO)
        let errPipe = Pipe()
        stderrPipe = errPipe
        dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.handlePipeData(handle: handle, originalFD: self.originalStderr, isError: true)
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isCapturing else { return }
        isCapturing = false

        // Set readabilityHandler to nil BEFORE restoring FDs to prevent races
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Restore stdout
        if originalStdout >= 0 {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            originalStdout = -1
        }
        stdoutPipe = nil

        // Restore stderr
        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
        stderrPipe = nil
    }

    /// Shared helper for both stdout and stderr pipe readability handlers.
    private func handlePipeData(handle: FileHandle, originalFD: Int32, isError: Bool) {
        let data = handle.availableData
        guard !data.isEmpty else { return }

        // Write to original FD so console output is preserved
        if originalFD >= 0 {
            data.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = write(originalFD, base, data.count)
                }
            }
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            handleOutput(text, isError: isError)
        }
    }

    private func handleOutput(_ text: String, isError: Bool) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        // Batch all lines into a single Task instead of one Task per line
        let entries = lines.map { line in
            PendingLogEntry(
                sessionID: sessionID,
                timestamp: Date(),
                category: .system,
                level: isError ? .warning : .info,
                message: line
            )
        }
        Task { [buffer, entries] in
            for entry in entries {
                await buffer.append(entry)
            }
        }
    }

    deinit {
        stop()
    }
}
#endif
