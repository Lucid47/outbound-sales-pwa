// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OutboundSalesNative",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "OutboundSalesNative", targets: ["OutboundSalesNative"])
    ],
    dependencies: [
        .package(path: "../OutboundSalesCore")
    ],
    targets: [
        .target(
            name: "OutboundSalesNative",
            dependencies: ["OutboundSalesCore"]
        )
    ]
)
