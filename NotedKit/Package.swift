// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotedKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NotedKit", targets: ["NotedKit"]),
    ],
    targets: [
        .target(
            name: "NotedKit",
            path: "Sources/NotedKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
