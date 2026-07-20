// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OutboundSalesCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "OutboundSalesCore", targets: ["OutboundSalesCore"])
    ],
    targets: [
        .target(name: "OutboundSalesCore"),
        .testTarget(name: "OutboundSalesCoreTests", dependencies: ["OutboundSalesCore"])
    ]
)
