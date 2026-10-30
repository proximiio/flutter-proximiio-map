// swift-tools-version: 5.9

import PackageDescription

// The map and SDK versions are pinned exactly and must match each other: the map binary pins the
// SDK binary at this same version. Keep the SDK pin equal to flutter_proximiio's.
let package = Package(
    name: "flutter_proximiio_map",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-proximiio-map", targets: ["flutter_proximiio_map"])
    ],
    dependencies: [
        .package(url: "https://github.com/proximiio/proximiio-map-ios-binary.git", exact: "6.0.0-beta.60"),
        .package(url: "https://github.com/proximiio/proximiio-sdk-ios-binary.git", exact: "6.0.0-beta.68"),
    ],
    targets: [
        .target(
            name: "flutter_proximiio_map",
            dependencies: [
                .product(name: "ProximiioMap", package: "proximiio-map-ios-binary"),
                .product(name: "Proximiio", package: "proximiio-sdk-ios-binary"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
