// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CustomerListOCR",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "customer-list-ocr", targets: ["CustomerListOCR"])
    ],
    targets: [
        .executableTarget(
            name: "CustomerListOCR",
            path: "Sources/CustomerListOCR"
        )
    ]
)
