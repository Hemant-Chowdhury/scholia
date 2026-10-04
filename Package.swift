// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Reader", targets: ["ReaderApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "DocumentKit"),
        .target(name: "AgentKit"),
        .target(name: "WorkspaceStore", dependencies: [
            "DocumentKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "Assistant", dependencies: ["DocumentKit", "WorkspaceStore", "AgentKit"]),
        .target(name: "ReaderUI", dependencies: ["DocumentKit", "WorkspaceStore", "AgentKit", "Assistant"]),
        .executableTarget(name: "ReaderApp", dependencies: ["ReaderUI", "WorkspaceStore"]),
        .target(name: "TestSupport", dependencies: ["AgentKit", "Assistant"], path: "Tests/TestSupport"),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit"]),
        .testTarget(name: "AssistantTests", dependencies: ["Assistant", "AgentKit", "WorkspaceStore", "DocumentKit", "TestSupport"]),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit", "TestSupport"]),
        .testTarget(name: "WorkspaceStoreTests", dependencies: ["WorkspaceStore", "DocumentKit", "TestSupport"]),
        .testTarget(name: "ReaderUITests", dependencies: ["ReaderUI", "WorkspaceStore", "DocumentKit", "TestSupport"]),
    ]
)
