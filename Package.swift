// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CollectionVGrid",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
    ],
    products: [
        .library(
            name: "CollectionVGrid",
            targets: ["CollectionVGrid"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.0.5"),
        .package(url: "https://github.com/ra1028/DifferenceKit", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CollectionVGrid",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "DifferenceKit", package: "DifferenceKit"),
            ]
        ),
    ]
)
