// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AdigaRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "adiga", targets: ["AdigaRunner"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.103.0")
    ],
    targets: [
        .executableTarget(
            name: "AdigaRunner",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
    ]
)
