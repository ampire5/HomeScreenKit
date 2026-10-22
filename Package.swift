// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomeScreenKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HomeScreenModel", targets: ["HomeScreenModel"]),
        .library(name: "HomeScreenKit", targets: ["HomeScreenKit"]),
        .library(name: "HomeChrome", targets: ["HomeChrome"]),
        .library(name: "FilmstripModel", targets: ["FilmstripModel"]),
    ],
    targets: [
        .target(name: "HomeScreenModel"),
        .target(name: "HomeChrome"),
        .target(name: "FilmstripModel"),
        .target(name: "HomeScreenKit", dependencies: ["HomeScreenModel", "HomeChrome"]),
        .executableTarget(name: "homescreen-demo", dependencies: ["HomeScreenKit"]),
        .testTarget(name: "HomeScreenModelTests", dependencies: ["HomeScreenModel"]),
        .testTarget(name: "HomeScreenKitTests", dependencies: ["HomeScreenKit"]),
        .testTarget(name: "HomeChromeTests", dependencies: ["HomeChrome"]),
        .testTarget(name: "FilmstripModelTests", dependencies: ["FilmstripModel"]),
    ],
    swiftLanguageModes: [.v5]
)
