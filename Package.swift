// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DocumentKit"),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit"]),
    ]
)
