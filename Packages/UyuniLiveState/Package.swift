// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UyuniLiveState",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UyuniLiveState", targets: ["UyuniLiveState"]),
        .executable(name: "UyuniLiveStateFixtureApplication", targets: ["UyuniLiveStateFixtureApplication"]),
    ],
    targets: [
        .target(name: "UyuniLiveState"),
        .executableTarget(name: "UyuniLiveStateFixtureApplication", dependencies: ["UyuniLiveState"]),
        .testTarget(name: "UyuniLiveStateTests", dependencies: ["UyuniLiveState"]),
    ],
    swiftLanguageModes: [.v6]
)
