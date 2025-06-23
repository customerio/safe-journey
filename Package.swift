// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SafeJourney",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .executable(
            name: "sj",
            targets: ["SafeJourneyChecker"]
        ),
        .library(
            name: "SafeJourney",
            targets: ["SafeJourney"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SafeJourneyChecker",
            dependencies: ["SafeJourney"],
            path: "Sources/Checker"
        ),
        .target(
            name: "SafeJourney",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/Library"
        ),
        .testTarget(
            name: "SafeJourneyTests",
            dependencies: ["SafeJourney", "SafeJourneyChecker"],
            path: "tests"
        )
    ]
)
