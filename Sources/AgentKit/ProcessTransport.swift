import Foundation

/// Runs an agent program and exchanges lines with it through stdin and stdout.
public final class ProcessTransport: LineTransport, @unchecked Sendable {
    public let lines: AsyncStream<String>
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var errorTail = Data()

    public init(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL) throws {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        lines = stream
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty { process.environment = environment }
        process.currentDirectoryURL = currentDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                self.flushRemainder(to: continuation)
                continuation.finish()
                return
            }
            self.receive(data, to: continuation)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.lock.withLock {
                self?.errorTail.append(data)
                if let tail = self?.errorTail, tail.count > 8192 { self?.errorTail = tail.suffix(8192) }
            }
        }
        try process.run()
    }

    /// The last part of the agent's error output, for error messages.
    public var stderrTail: String { lock.withLock { String(decoding: errorTail, as: UTF8.self) } }

    public var isRunning: Bool { process.isRunning }

    public func send(_ line: String) async throws {
        let data = Data((line + "\n").utf8)
        try lock.withLock { try input.fileHandleForWriting.write(contentsOf: data) }
    }

    public func close() async {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func receive(_ data: Data, to continuation: AsyncStream<String>.Continuation) {
        let complete: [String] = lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        complete.filter { !$0.isEmpty }.forEach { continuation.yield($0) }
    }

    private func flushRemainder(to continuation: AsyncStream<String>.Continuation) {
        let rest = lock.withLock { () -> String in
            defer { buffer.removeAll() }
            return String(decoding: buffer, as: UTF8.self)
        }
        if !rest.isEmpty { continuation.yield(rest) }
    }
}
