// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "CodexBeacon",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "CodexBeaconCore", targets: ["CodexBeaconCore"]),
    .executable(name: "CodexBeacon", targets: ["CodexBeacon"]),
  ],
  targets: [
    .target(name: "CodexBeaconCore"),
    .executableTarget(
      name: "CodexBeacon",
      dependencies: ["CodexBeaconCore"]
    ),
    .testTarget(
      name: "CodexBeaconCoreTests",
      dependencies: ["CodexBeaconCore"]
    ),
    .testTarget(
      name: "CodexBeaconTests",
      dependencies: ["CodexBeacon", "CodexBeaconCore"]
    ),
  ]
)
