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
    targets: [
        .target(
            name: "CollectionVGrid"
        ),
        .testTarget(
            name: "CollectionVGridTests",
            dependencies: ["CollectionVGrid"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
