import Foundation
import Testing
@testable import DocumentKit

struct ContentHashTests {
    private func writeTemp(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func hashOfKnownBytesMatchesSHA256() throws {
        let url = try writeTemp("abc")
        #expect(try ContentHash.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sameBytesAtDifferentPathsGiveSameHash() throws {
        #expect(try ContentHash.sha256(of: writeTemp("same")) == ContentHash.sha256(of: writeTemp("same")))
    }

    @Test func missingFileThrows() {
        #expect(throws: (any Error).self) {
            try ContentHash.sha256(of: URL(fileURLWithPath: "/nonexistent/file.pdf"))
        }
    }
}
