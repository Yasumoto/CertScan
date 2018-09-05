// swift-tools-version:4.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CertScan",
    dependencies: [
        .package(url: "https://github.com/swift-aws/aws-sdk-swift", .branch("jmsmith-multiple-targets")),
    ],
    targets: [
        .target(
            name: "CertScan",
            dependencies: ["Iam"]),
        .testTarget(
            name: "CertScanTests",
            dependencies: ["CertScan"]),
    ]
)
