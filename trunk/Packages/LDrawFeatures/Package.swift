// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawFeatures",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawFeatures", targets: ["LDrawFeatures"]),
    ],
    dependencies: [
        .package(path: "../LDrawCore"),
    ],
    targets: [
        .target(
            name: "LDrawFeatures",
            dependencies: [
                .product(name: "LDrawCore", package: "LDrawCore"),
            ],
            path: "Sources/LDrawFeatures",
            publicHeadersPath: "include",
            cSettings: [
                .define("WANT_RELATED_PARTS", to: "1"),
            ]
        ),
    ]
)
