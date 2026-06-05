// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "oh-my-display",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "OMDCore", targets: ["OMDCore"]),
    .executable(name: "OhMyDisplay", targets: ["OhMyDisplay"]),
    .executable(name: "omd", targets: ["omd"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0")
  ],
  targets: [
    .target(
      name: "OMDQuartzBridge",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("QuartzCore"),
        .linkedFramework("CoreGraphics"),
      ]
    ),
    .target(
      name: "OMDCore",
      dependencies: ["OMDQuartzBridge"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("ColorSync"),
        .linkedFramework("IOKit"),
      ]
    ),
    .target(
      name: "OMDCLI",
      dependencies: [
        "OMDCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .target(
      name: "OMDAppCore",
      dependencies: ["OMDCore"]
    ),
    .executableTarget(
      name: "OhMyDisplay",
      dependencies: ["OMDAppCore", "OMDCore"],
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .executableTarget(
      name: "omd",
      dependencies: [
        "OMDCLI"
      ]
    ),
    .testTarget(
      name: "OMDCoreTests",
      dependencies: ["OMDCore", "OMDQuartzBridge"]
    ),
    .testTarget(
      name: "OMDCLITests",
      dependencies: ["OMDCLI"]
    ),
    .testTarget(
      name: "OMDAppCoreTests",
      dependencies: ["OMDAppCore"]
    ),
  ]
)
