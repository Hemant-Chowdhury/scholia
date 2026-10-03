// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "DocumentKit"),
        .target(name: "WorkspaceStore", dependencies: [
            "DocumentKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit", "TestSupport"]),
        .testTarget(name: "WorkspaceStoreTests", dependencies: ["WorkspaceStore", "DocumentKit", "TestSupport"]),
    ]
)
