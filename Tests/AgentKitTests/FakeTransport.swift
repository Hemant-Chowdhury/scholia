import Foundation
@testable import AgentKit

/// An in-memory line transport. Tests read what the client sent and push lines from the "agent".
final class FakeTransport: LineTransport, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let input: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var _sent: [String] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init() {
        (lines, input) = AsyncStream.makeStream(of: String.self)
    }

    var sent: [String] { lock.withLock { _sent } }

    func sentJSON(_ index: Int) -> JSONValue? { JSONRPCConnection.parseLine(sent[index]) }

    func send(_ line: String) async throws {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
            _sent.append(line)
            let count = _sent.count
            let done = waiters.filter { $0.0 <= count }.map(\.1)
            waiters.removeAll { $0.0 <= count }
            return done
        }
        ready.forEach { $0.resume() }
    }

    func close() async { input.finish() }

    func push(_ line: String) { input.yield(line) }

    func finish() { input.finish() }

    /// Waits until the client has sent at least `count` lines.
    func waitForSent(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if _sent.count >= count { return true }
                waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
