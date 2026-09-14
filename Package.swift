// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ARGUS", platforms: [.macOS(.v14)],
  products: [
    .library(name: "ArgusCore", targets: ["ArgusCore"]),
    .executable(name: "ARGUS", targets: ["ArgusApp"]),
  ],
  targets: [
    .target(name: "ArgusCore"),
    .systemLibrary(name: "CSQLite"),
    .target(name: "ArgusStore", dependencies: ["ArgusCore", "CSQLite"]),
    .target(name: "ArgusPlatform", dependencies: ["ArgusCore", "ArgusStore"]),
    .target(name: "ArgusPresentation", dependencies: ["ArgusCore", "ArgusStore", "ArgusPlatform"]),
    .executableTarget(name: "ArgusApp", dependencies: ["ArgusPresentation", "ArgusStore", "ArgusPlatform"]),
    .testTarget(name: "ArgusCoreTests", dependencies: ["ArgusCore"]),
    .testTarget(name: "ArgusStoreTests", dependencies: ["ArgusStore", "ArgusCore", "CSQLite"]),
    .testTarget(name: "ArgusPlatformTests", dependencies: ["ArgusPlatform", "ArgusStore", "ArgusCore"]),
    .testTarget(name: "ArgusPresentationTests", dependencies: ["ArgusPresentation", "ArgusCore", "ArgusStore", "ArgusPlatform", "CSQLite"]),
  ])
