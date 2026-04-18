// swift-tools-version: 6.1

// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import PackageDescription

let package = Package(
    name: "AdigaRunner",
    platforms: [
        .macOS(.v15)
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
