import Foundation

/// Tests that open real windows run only on a Mac with a user session; CI runners skip them (GitHub sets CI=true).
public enum WindowTests {
    public static let available = ProcessInfo.processInfo.environment["CI"] == nil
}
