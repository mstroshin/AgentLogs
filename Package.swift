// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AgentLogs",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "AgentLogsCore", targets: ["AgentLogsCore"]),
        .library(name: "AgentLogsSDK", targets: ["AgentLogsSDK"]),
        .executable(name: "agent-logs", targets: ["AgentLogsCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "AgentLogsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // MARK: - SDK
        .target(
            name: "AgentLogsSDK",
            dependencies: [
                "AgentLogsCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),

        // MARK: - CLI
        .executableTarget(
            name: "AgentLogsCLI",
            dependencies: [
                "AgentLogsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "AgentLogsCoreTests",
            dependencies: ["AgentLogsCore"]
        ),
        .testTarget(
            name: "AgentLogsSDKTests",
            dependencies: ["AgentLogsSDK"]
        ),
        .testTarget(
            name: "AgentLogsCLITests",
            dependencies: ["AgentLogsCore"]
        ),
    ]
)
