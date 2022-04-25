// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Query",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(name: "Query", targets: ["Query"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Nimble", from: "9.2.1")
    ],
    targets: [
        .target(name: "Query", dependencies: []),
        .testTarget(name: "QueryTests", dependencies: ["Query", "Nimble"], resources: [.process("QueryTests/QueryTests.xcdatamodeld")])
    ]
)
