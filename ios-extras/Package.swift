// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KUpergramExtras",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "KUpergramExtras", targets: ["KUpergramExtras"]),
    ],
    targets: [
        .target(name: "KUpergramExtras", path: "Sources/KUpergramExtras"),
    ]
)
