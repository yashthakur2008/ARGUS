// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ARGUS", platforms: [.macOS(.v14)],
  products: [.library(name: "ArgusCore", targets: ["ArgusCore"])],
  targets: [
    .target(name: "ArgusCore"), .testTarget(name: "ArgusCoreTests", dependencies: ["ArgusCore"]),
  ])
