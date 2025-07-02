// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CollectionVGrid",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "CollectionVGrid",
            targets: ["CollectionVGrid"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ra1028/DifferenceKit", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CollectionVGrid",
            dependencies: [
                .product(name: "DifferenceKit", package: "DifferenceKit"),
            ]
        ),
    ]
)
