// swift-tools-version:4.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CertScan",
    dependencies: [
        .package(url: "https://github.com/swift-aws/aws-sdk-swift", .branch("jmsmith-multiple-targets")),
        .package(url: "https://github.com/apple/swift-nio-ssl", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "CertScan",
            dependencies: ["Iam", "NIOOpenSSL"]),
        .testTarget(
            name: "CertScanTests",
            dependencies: ["CertScan"]),
    ]
)
