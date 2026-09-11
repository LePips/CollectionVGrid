// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CollectionVGrid",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v15),
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
        .testTarget(
            name: "CollectionVGridTests",
            dependencies: ["CollectionVGrid"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
